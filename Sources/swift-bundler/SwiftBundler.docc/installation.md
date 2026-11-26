# Installation

Installing Swift Bundler on your system.

## Recommended method

Swift Bundler releases now include pre-built installers/redistributables. The following one-liners use those to install Swift Bundler in a matter of seconds (with a good enough internet connection).

### macOS / Linux

```sh
curl -fsSL https://sbun.dev/install.sh | sh
```

### Windows

```sh
powershell -c "irm sbun.dev/install.ps1|iex"
```

> Warning: Make sure to always run Swift Bundler from Native Tools Command Prompt for VS 2022 so that Swift Bundler can locate required tools such as `dumpbin`.

> Note: Continue to <doc:installation#Runtime-dependencies> to install required runtime dependencies.

## Manual installation

Recent Swift Bundler releases include installers for macOS, Windows, and Linux (RPM-based, loose .tar.gz, or standalone). Download an installer of your choice and run it, or a loose binary/directory and place it on your path. Remember to create an `sbun` symlink on your path if you want to follow along with our tutorials.

```sh
# Verify installation
swift-bundler --version
sbun --version
```

> Note: Continue to <doc:installation#Runtime-dependencies> to install required runtime dependencies.

## From source

You can install Swift Bundler manually for maximum control. Clone the repo,
build Swift Bundler using the Swift Package Manager, and then copy the
resulting executable to a directory in your path.

```sh
git clone https://github.com/moreSwift/swift-bundler
cd swift-bundler

# SBUN_NO_SCHEMA_GEN speeds up release builds by working around a Swift Syntax
# prebuilts issue (which may get resolved in future Swift versions)
SBUN_NO_SCHEMA_GEN=1 swift build -c release
cp .build/release/swift-bundler /path/to/bin/swift-bundler
ln -s /path/to/bin/swift-bundler /path/to/bin/sbun

# Verify installation
swift-bundler --version
sbun --version
```

> Note: Continue to <doc:installation#Runtime-dependencies> to install required runtime dependencies.

## Runtime dependencies

Install the following runtime dependencies to ensure full functionality.

### macOS

Swift Bundler has no runtime dependencies on macOS outside of the Xcode toolchain.

### Linux

On Linux you'll need to install `patchelf`. There also two bundler-specific
dependencies; `rpmbuild` for the `linuxRPM` bundler, and `appimagetool` for the
`linuxAppImage` bundler.

#### patchelf (required)

[patchelf](https://github.com/NixOS/patchelf) is used to relocate dynamic libraries during bundling. Modern Linux distributions generally have patchelf in their official repository. If yours doesn't, the [patchelf GitHub repository](https://github.com/NixOS/patchelf) has binary downloads attached to every release.

@TabNavigator {
    @Tab("Debian-based distros") {
        ```shell
        sudo apt install patchelf
        ```
    }
    @Tab("Fedora-based distros") {
        ```shell
        sudo dnf install patchelf
        ```
    }
}

#### rpmbuild (required for RPM bundling)

rpmbuild is used by Swift Bundler's RPM bundler to produce RPM packages. You don't need to use an RPM-based distribution to produce RPM packages.

@TabNavigator {
    @Tab("Debian-based distros") {
        ```shell
        sudo apt install rpm
        ```
    }
    @Tab("Fedora-based distros") {
        ```shell
        sudo dnf install rpmdevtools
        ```
    }
}

#### appimagetool (required for AppImage bundling)

[appimagetool](https://appimage.github.io/appimagetool/) is used by Swift Bundler's AppImage bundler to produce AppImages. It's shipped as an AppImage, not a system package, so installation is a little more manual.

1. Download the latest build from the [releases page](https://github.com/AppImage/appimagetool/releases). Make sure to get the one for your architecture.
2. Run `chmod +x ./appimagetool-ARCH.AppImage` to make the downloaded file executable.
3. Run `sudo mv ./appimagetool-ARCH.AppImage /usr/local/bin/appimagetool` to install it system-wide.

### Windows

Swift Bundler has no runtime dependencies on Windows outside of the Visual Studio toolchain.

> Warning: Make sure to always run Swift Bundler from Native Tools Command Prompt for VS 2022 so that Swift Bundler can locate required tools such as `dumpbin`.
