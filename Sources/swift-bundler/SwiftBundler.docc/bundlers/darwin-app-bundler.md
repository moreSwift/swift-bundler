# Darwin app bundler

A bundler that produces Darwin app bundles for Apple platforms.

## Overview

The Darwin app bundler produces the `.app` bundles that you know and love. It's currently the only bundler for Apple platforms.

## Usage

In all of the following examples you can omit `--bundler darwinApp` because it is the default when targeting Apple platforms.

### Create an app bundle

```sh
sbun bundle --bundler darwinApp
```

### Run on your Mac

```sh
sbun run --bundler darwinApp
```

### Run on your Mac using Mac Catalyst

```sh
sbun run --platform macCatalyst
```

### Run on an iOS/tvOS/visionOS device

```sh
sbun run --device "Your Device"
```

### Run on an iOS/tvOS/visionOS simulator

```sh
sbun run --simulator "Your Simulator"
```
