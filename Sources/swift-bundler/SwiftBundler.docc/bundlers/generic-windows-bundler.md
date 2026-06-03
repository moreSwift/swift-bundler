# Generic Window bundler

The default Windows bundler.

## Overview

The generic Windows bundler bundles your main executable, required dynamic libraries, and resources in a single flat directory, as is common for manually distributed Windows applications.

It is the recommended bundler to use during Windows development, as it's the fastest, and produces the most inspectable output bundle. If you wish, you can also use this bundler to distribute your application by zipping the resulting directory (as long as you tell your users to install required system dependencies).

This bundler forms the base for all of the other Windows bundlers.

## Usage

In all of the following examples you can omit `--bundler genericWindows` because it is the default when targeting Windows.

### Create an app bundle

```sh
swift-bundler bundle --bundler genericWindows
```

### Run on your host machine

```sh
swift-bundler run --bundler genericWindows
```
