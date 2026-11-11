# Linux packages

```sh
python3 Distribution/linux/build.py all
```

Produces:

```
Distribution/out/linux/swift-bundler-<version>-linux-<arch>.tar.gz
Distribution/out/linux/swift-bundler_<version>-1_<debarch>.deb
Distribution/out/linux/swift-bundler-<version>-1.<rpmarch>.rpm
```

The `.deb`, `.rpm`, and loose tarball share one staging tree. Each installs
`sbun` as a symlink to `swift-bundler`, and shell completions for both command
names.

## Static Linux SDK

The build uses the official Swift Static Linux SDK, so the resulting executable
is fully statically linked. It has no Swift runtime, C library, or other
runtime library dependencies and can be installed on any Linux distribution
with a compatible kernel.

If the matching SDK is not already installed, the script downloads it from
`download.swift.org` into `Distribution/out/linux/sdk/` and installs it with
`swift sdk install`. Set `SBUN_STATIC_LINUX_SDK` to an installed SDK selector
to skip the download.

The script automatically applies Musl compatibility workarounds to the
resolved SwiftPM checkouts for the pinned Yams 5.x (`DBL_DECIMAL_DIG`),
TOMLKit 0.7.x (missing `import Musl`), and swift-inotify (imports `Glibc`
directly) releases, which predate Static Linux SDK support. These patches only
touch `.build/checkouts`.

Prerequisites: `dpkg-deb` for `.deb`, `rpmbuild` for `.rpm`, and network access
the first time the Static Linux SDK is downloaded.
On Ubuntu: `sudo apt install dpkg rpm`.

`patchelf` and `rpm-build` remain optional runtime tools for Swift Bundler's
own Linux and RPM bundlers; they are not needed to build these packages.
