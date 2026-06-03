# AppImage bundler

A bundler that produces Linux AppImages.

## Overview

The AppImage bundler produces Linux [AppImages](https://appimage.org/) which are self contained executable files that don't require installation.

## Dependencies

The AppImage bundler relies on `appimagetool`, and `patchelf`.

### Installing appimagetool

Download a recent release of appimagetool from the [appimagetool releases page](https://github.com/AppImage/appimagetool/releases) on GitHub.

Then move it to a location on your PATH and mark it as executable,

```sh
sudo mv appimagetool-$(uname -m).AppImage /usr/local/bin/appimagetool
chmod +x /usr/local/bin/appimagetool
```

### Installing patchelf

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

## Usage

## Create an AppImage

```sh
swift-bundler bundle --bundler linuxAppImage
```

## Create and run an AppImage

```sh
swift-bundler run --bundler linuxAppImage
```
