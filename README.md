# rules_xcode_download

Automatically download Xcode from a given URL, and configure the
`xcode_version` rules.

## Usage

In your `MODULE.bazel`

```bzl
xcode = use_extension("@rules_xcode_download//:defs.bzl", "xcode")
xcode.download(
    integrity = "sha256-???",
    path = "/Applications/Xcode-26.3.0.17C529"  # This must be unique
    url = "/url/of/Xcode.xip",
)
use_repo(xcode, "xcode")
```

In your `.bazelrc`:

```
build --xcode_version_config=@xcode//:downloaded_xcode
```

The first time you build Xcode will be installed and then force you to
locally accept the license with something like:

```sh
DEVELOPER_DIR=/Applications/Xcode-26.3.0.17C529 xcodebuild -runFirstLaunch
```

Afterwards you can build as normal and bazel will use the tools from the
downloaded version.

Alternatively you can look at [`tools/bazel`](tools/bazel) for a
potential hack around having to do multiple bazel invocations before
things work. It's hard to enumerate all the possible install state of
Xcode's developer tools, but that potentially solves 1 common case.
