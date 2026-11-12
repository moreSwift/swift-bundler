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

- **Matching open-source Swift toolchain.** The Static Linux SDK ships modules
  built by the open-source toolchain, and Xcode's toolchain refuses to read
  them (it also ships without the Linux linker). Install the same version as
  the SDK—the script installs whichever SDK matches `swift --version`—and
  select it with `SBUN_TOOLCHAIN_BIN`:

  ```sh
  swiftly install 6.3.1
  export SBUN_TOOLCHAIN_BIN="$HOME/Library/Developer/Toolchains/swift-6.3.1-RELEASE.xctoolchain/usr/bin"
  python3 Distribution/linux/build.py all
  ```

  (On macOS, swiftly installs toolchains under
  `~/Library/Developer/Toolchains`; adjust the path if yours lives elsewhere.)

  The script probes the toolchain by building a tiny Foundation program for
  Linux before the real build, so an unusable toolchain fails immediately with
  this explanation instead of an opaque serialized-module error.
- **Linux linker tools.** The toolchain provides `swift-autolink-extract` and
  `ld.lld`; the script finds them on `PATH` (which `SBUN_TOOLCHAIN_BIN` feeds),
  or falls back to scanning `/Library/Developer/Toolchains`,
  `~/Library/Developer/Toolchains`, and `~/.swiftly/toolchains`. Point
  `SBUN_LINUX_LINKER_TOOLS` at a directory containing them to override the
  search:

  ```sh
  SBUN_LINUX_LINKER_TOOLS="/path/to/toolchain/usr/bin" \
    python3 Distribution/linux/build.py all
  ```
- **`dpkg-deb` and `rpmbuild`.** Both package foreign architectures from macOS:

  ```sh
  brew unlink rpm2cpio   # if installed; it conflicts with rpm
  brew install dpkg rpm
  ```

  `dpkg-deb` writes the `.deb` directly. Homebrew's `rpmbuild` only permits the
  host architecture by default, so the script generates a private `rpmrc` that
  declares the requested target architecture compatible (the spec itself never
  compiles anything—it only copies the already-built staged files). Homebrew's
  rpm also omits rpm's `elfdeps` helper, which only affects automatic
  ELF-derived dependencies; the executable is static, so it has none.

Because a Linux executable cannot run on macOS, the staging step generates the
shell completions with a host-native build of the same version instead of
executing the Linux binary. Set `SBUN_COMPLETIONS_BINARY` to an existing
`swift-bundler` binary to skip that extra build. The static-link checks that
can run on macOS (`file`) still run, but `ldd` and `--version` are skipped, so
smoke-test the resulting packages on Linux before publishing them.
