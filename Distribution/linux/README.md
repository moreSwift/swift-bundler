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
is fully statically linked. It has no runtime dependencies and can be installed
on any Linux distribution with a compatible kernel.

If a compatible Swift Static Linux SDK is not already installed, the script
downloads it from `download.swift.org` into `Distribution/out/linux/sdk/` and
installs it with `swift sdk install`. Set `SBUN_STATIC_LINUX_SDK` to an installed
SDK selector to skip the download.

**Prerequisites**: `dpkg-deb` for `.deb`, `rpmbuild` for `.rpm`, and network access
to download a Static Linux SDK if required.
On Ubuntu: `sudo apt install dpkg rpm`.

## Cross-compiling on macOS

The same script cross-compiles the Linux artifacts on macOS:

```sh
python3 Distribution/linux/build.py all                 # x86_64 by default
python3 Distribution/linux/build.py all --arch aarch64
```

`--arch` defaults to `x86_64` on macOS (and to the host architecture
everywhere else); any other architecture on a non-macOS host is still
rejected, because the script never emulates.

Requirements on macOS:

- **An open-source Swift toolchain.** Using the Static Linux SDK requires a
  matching open source Swift toolchain. Once you have an open source
  Swift toolchain, the script automatically installs whichever SDK matches
  `swift --version`:

  ```sh
  swiftly install 6.3.1
  export SBUN_TOOLCHAIN_BIN="$HOME/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain/usr/bin"
  python3 Distribution/linux/build.py all
  ```

  (On macOS, swiftly installs toolchains under
  `~/Library/Developer/Toolchains`; adjust the path if yours lives elsewhere.)
- **`dpkg-deb` and `rpmbuild`.**

  ```sh
  brew unlink rpm2cpio   # unlink rpm2cpio if installed; it conflicts with rpm
  brew install dpkg rpm
  ```

Because a Linux executable cannot run on macOS, the staging step generates the
shell completions with a host build of Swift Bundler. Set `SBUN_COMPLETIONS_BINARY`
to an existing `swift-bundler` binary to skip that extra build.
