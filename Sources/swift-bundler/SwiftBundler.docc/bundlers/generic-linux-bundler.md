# Generic Linux bundler

The default Linux bundler.

## Overview

The generic Linux bundler generates a directory structure—reminiscent of the structure laid out by the [Filesystem Hierarchy Standard](https://en.wikipedia.org/wiki/Filesystem_Hierarchy_Standard)—that houses your main executable, required dynamic libraries, and resources.

It is the recommended bundler to use during Linux development, as it's the fastest, and produces the most inspectable output bundle. If you wish, you can also use this bundler to distribute your application by archiving the resulting directory (as long as you tell your users to install required system dependencies).

This bundler forms the base for all of the other Linux bundlers.

## Usage

In all of the following examples you can omit `--bundler genericLinux` because it is the default when targeting Linux.

### Create an app bundle

```sh
swift-bundler bundle --bundler genericLinux
```

### Run on your host machine

```sh
swift-bundler run --bundler genericLinux
```
