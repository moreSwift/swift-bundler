# APK bundler

A bundler that produces Android APKs.

## Overview

The APK bundler is the recommended bundler to use when developing and
distributing Android applications.

## Usage

You can omit `--bundler androidAPK` when Swift Bundler can infer that the target platform is `Android`, because the default Android bundler is the APK bundler. This includes using the `--platform android` argument to specifically target Android.

### Create an APK

```sh
swift-bundler bundle --bundler androidAPK
```

### Create an optimized APK

```sh
swift-bundler bundle --bundler androidAPK -c release --strip
```

### Run on an Android device

```sh
swift-bundler run --device "Your Pixel 8a"
```

### Run on an Android emulator

```sh
swift-bundler run --simulator "Pixel 8a"
```
