"""Automatically download and configure an Xcode version."""

load("@bazel_features//:features.bzl", "bazel_features")

def _run(mctx, args, **kwargs):
    result = mctx.execute(args, **kwargs)
    if result.return_code != 0:
        fail("command '{}' failed with code '{}', stdout: '{}', stderr: '{}'"
            .format(args, result.return_code, result.stdout, result.stderr))
    return result.stdout

def _get_sdk_version(mctx, name, xcode_path):
    # /Applications/Xcode.app/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/SDKSettings.json
    output = json.decode(mctx.read(
        str(xcode_path) + "/Contents/Developer/Platforms/{name}.platform/Developer/SDKs/{name}.sdk/SDKSettings.json".format(name = name),
        watch = "no",
    ))
    return output["Version"]

def _check_license_accept(mctx, xcode_path):
    result = mctx.execute(
        ["xcodebuild", "-checkFirstLaunchStatus"],
        environment = {"DEVELOPER_DIR": str(xcode_path)},
    )
    if result.return_code == 0:
        return

    fail("Xcode license not accepted. Please run 'DEVELOPER_DIR={} sudo xcodebuild -runFirstLaunch' to accept the license and build again.".format(xcode_path))

_xcode_repo = repository_rule(
    implementation = lambda rctx: rctx.file("BUILD.bazel", content = rctx.attr.build_file_content),
    attrs = {
        "build_file_content": attr.string(mandatory = True),
    },
)

def _xcode_impl(mctx):
    download_info = None
    for module in mctx.modules:
        if not module.is_root:
            continue

        tags = module.tags.download
        if len(tags) != 1:
            fail("xcode.download must be called exactly once")
        download_info = tags[0]

    if not download_info.sha256 and not download_info.integrity:
        fail("xcode.download must specify either sha256 or integrity")

    output_path = mctx.path(download_info.path)

    temporary_output = "xcode.xip"
    if not output_path.is_dir:
        mctx.download(
            url = download_info.url,
            sha256 = download_info.sha256,
            integrity = download_info.integrity,
            output = temporary_output,
        )

        unxip_dir = mctx.path("/tmp/rules_xcode_download_DO_NOT_USE")
        _run(mctx, ["rm", "-rf", unxip_dir])
        _run(mctx, ["mkdir", "-p", unxip_dir])
        _run(mctx, ["cp", "-c", temporary_output, unxip_dir])

        mctx.report_progress("Extracting Xcode.xip, this may take a while...")
        _run(
            mctx,
            ["xip", "--expand", "xcode.xip"],
            working_directory = str(unxip_dir),
        )

        # NOTE: Output can be either Xcode.app or Xcode-beta.app, so we look for any .app
        files = unxip_dir.readdir(watch = "no")
        app = None
        for file in files:
            if file.basename.endswith(".app"):
                app = file
                break
        if not app:
            fail("failed to extract an .app, please report an issue with this list: " + ", ".join([f for f in files]))

        _run(mctx, ["mv", app, output_path])

    _check_license_accept(mctx, output_path)
    info_plist = json.decode(_run(
        mctx,
        ["plutil", "-convert", "json", "-o", "-", "Contents/version.plist"],
        working_directory = str(output_path),
    ))

    xcode_version = info_plist["CFBundleShortVersionString"]
    if len(xcode_version.split(".")) == 2:
        xcode_version += ".0"

    xcode_version += "." + info_plist["ProductBuildVersion"]
    ios_sdk_version = _get_sdk_version(mctx, "iPhoneOS", output_path)
    macos_sdk_version = _get_sdk_version(mctx, "MacOSX", output_path)
    tvos_sdk_version = _get_sdk_version(mctx, "AppleTVOS", output_path)
    visionos_sdk_version = _get_sdk_version(mctx, "XROS", output_path)
    watchos_sdk_version = _get_sdk_version(mctx, "WatchOS", output_path)

    _xcode_repo(
        name = "xcode",
        build_file_content = """\
load("@apple_support//xcode:xcode_config.bzl", "xcode_config")
load("@apple_support//xcode:xcode_version.bzl", "xcode_version")

xcode_version(
    name = "{xcode_version}",
    default_ios_sdk_version = "{ios_sdk_version}",
    default_macos_sdk_version = "{macos_sdk_version}",
    default_tvos_sdk_version = "{tvos_sdk_version}",
    default_visionos_sdk_version = "{visionos_sdk_version}",
    default_watchos_sdk_version = "{watchos_sdk_version}",
    version = "{xcode_version}",
)

xcode_config(
    name = "downloaded_xcode",
    default = ":{xcode_version}",
    versions = [":{xcode_version}"],
)
""".format(
            ios_sdk_version = ios_sdk_version,
            macos_sdk_version = macos_sdk_version,
            tvos_sdk_version = tvos_sdk_version,
            visionos_sdk_version = visionos_sdk_version,
            watchos_sdk_version = watchos_sdk_version,
            xcode_version = xcode_version,
        ),
    )

    metadata_kwargs = {}
    if bazel_features.external_deps.extension_metadata_has_reproducible:
        metadata_kwargs["reproducible"] = True
    return mctx.extension_metadata(**metadata_kwargs)

_download_tag = tag_class(
    attrs = {
        "url": attr.string(mandatory = True),
        "path": attr.string(mandatory = True),
        "sha256": attr.string(),
        "integrity": attr.string(),
        "strip_prefix": attr.string(),
    },
)
xcode = module_extension(
    implementation = _xcode_impl,
    tag_classes = {
        "download": _download_tag,
    },
)
