# RPM bundler

A bundler that produces Linux RPM installers.

## Overview

The RPM bundler is one of the bundlers that we recommend when distributing Linux applications.

The output of the RPM bundler is not directly runnable, so it is incompatible
with the `swift-bundler run` command.

## Dependencies

The RPM bundler relies on the `rpmbuild` command, and the `patchelf` command.

@TabNavigator {
    @Tab("Debian-based distros") {
        ```shell
        sudo apt install rpm patchelf
        ```
    }
    @Tab("Fedora-based distros") {
        ```shell
        sudo dnf install rpmdevtools patchelf
        ```
    }
}

## Usage

### Create an RPM installer

```sh
swift-bundler bundle --bundler linuxRPM
```

### Create an optimized RPM installer

```sh
swift-bundler bundle --bundler linuxRPM -c release --strip
```

## Testing installers on non-RPM distros

Sometimes it's most convenient to test RPM installers on your own machine even
if your chosen Linux distribution doesn't use the RPM package manager or a
derivative thereof.

> Warning: Proceed with caution. This is not a supported usecase of RPM. RPM
is a low-level tool that generally isn't designed to be used directly by users,
and especially not on Linux systems with competing package managers. We do not
take liability for anything that happens as a result of following these
instructions.

First, install the `rpm` CLI. On Ubuntu you can do that like so,

```sh
sudo apt install rpm
```

Next, locate your RPM installer and install it with this command,

```sh
sudo rpm -i --nodeps path/to/yourapp.rpm
```

To check that your package has been installed, you can get RPM to list all installed packages,

```sh
sudo rpm -qa
```

To remove your application, take note of the name given to your package in the output of the above command, and run the following command after substituting the package name,

```sh
sudo rpm -e <packagename>
```
