# Installation

Installing Swift Bundler on your system.

## Recommended (macOS and Linux)

If you're on macOS or Linux, install the latest version of Swift Bundler using
[Mint](https://github.com/yonaskolb/Mint).

If you have previously installed Swift Bundler via the installation script you must delete the `/opt/swift-bundler` directory (requires sudo).

Swift Bundler hasn't had an official release in a while due to some outstanding
breaking changes to be made before 3.0, so we recommend installing directly from
the main branch.

```sh
mint install stackotter/swift-bundler@main
```

> Note: Continue to <doc:installation#Runtime-dependencies> to install required runtime dependencies.

## Manual installation (all platforms)

You can install Swift Bundler manually for maximum control. Clone the repo,
build Swift Bundler using the Swift Package Manager, and then copy the
resulting executable to a directory in your path.

```sh
git clone https://github.com/moreSwift/swift-bundler
cd swift-bundler

# SBUN_NO_SCHEMA_GEN speeds up release builds by working around a Swift Syntax
# prebuilts issue (which may get resolved in future Swift versions)
SBUN_NO_SCHEMA_GEN=1 swift build -c release
cp .build/release/swift-bundler /path/to/bin/

# Verify installation
swift bundler --version
```

> Note: Continue to <doc:installation#Runtime-dependencies> to install required runtime dependencies.

## Pre-built (macOS)

If you're on macOS, you can use the universal build of `swift-bundler` attached
to recent releases.

```sh
# Replace X.X.X with desired version
curl -O https://github.com/moreSwift/swift-bundler/releases/download/vX.X.X/swift-bundler
chmod +x ./swift-bundler
sudo mv ./swift-bundler /usr/local/bin/

# Verify installation
swift bundler --version
```

## Runtime dependencies

Install the following runtime dependencies to ensure full functionality.

### macOS

Swift Bundler has no runtime dependencies on macOS outside of the Xcode toolchain.

### Linux

On Linux you'll need to install `patchelf`. There also two bundler-specific dependencies; `rpmbuild` for the `linuxRPM` bundler, and `appimagetool` for the `linuxAppImage` bundler.

#### patchelf (required)

[patchelf](https://github.com/NixOS/patchelf) is used to relocate dynamic libraries during bundling. Modern Linux distributions generally have patchelf in their official repository. If yours doesn't, the [patchelf GitHub repository](https://github.com/NixOS/patchelf) has binary downloads attached to every release.

```sh
# Ubuntu, Debian
sudo apt install patchelf

# Fedora
sudo dnf install patchelf
```

#### rpmbuild (required for RPM bundling)

rpmbuild is used by Swift Bundler's RPM bundler to produce RPM packages. You don't need to use an RPM-based distribution to produce RPM packages.

```sh
# Ubuntu, Debian
sudo apt install rpm

# Fedora
sudo dnf install rpmdevtools
```

#### appimagetool (required for AppImage bundling)

[appimagetool](https://appimage.github.io/appimagetool/) is used by Swift Bundler's AppImage bundler to produce AppImages. It's shipped as an AppImage, not a system package, so installation is a little more manual.

1. Download the latest build from the [releases page](https://github.com/AppImage/appimagetool/releases). Make sure to get the one for your architecture.
2. Run `chmod +x ./appimagetool-ARCH.AppImage` to make the downloaded file executable.
3. Run `sudo mv ./appimagetool-ARCH.AppImage /usr/local/bin/appimagetool` to install it system-wide.

### Windows

Swift Bundler has no runtime dependencies on Windows outside of the Visual Studio toolchain.

> Warning: Make sure to always run Swift Bundler from Native Tools Command Prompt for VS 2022 so that Swift Bundler can locate required tools such as `dumpbin`.
