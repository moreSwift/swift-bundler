# Creating an app

Creating a hello world app.

## Overview

Use the following command to create a new app from the [SwiftCrossUI](https://swiftcrossui.dev) template.

```sh
# Create a new app from the SwiftCrossUI template
sbun create HelloWorld --template SwiftCrossUI
cd HelloWorld
```

To learn more about package templates, see <doc:package-templates>.

## Running the app

Use the `run` command to build and run the app;

```sh
sbun run
```

On a simulator;

```sh
# Run the app on an iOS simulator.
sbun run --simulator "iPhone 16"
```

Or on a physical device;

```sh
# Run the app on an Android device.
sbun run --device "Pixel 7"
```

## Distributing the app

Use the `bundle` command to create an app bundle that you can distribute to
users.

On macOS it is recommended that you use the `-c release -u` options to create
an optimized universal binary (for running on both Intel and Apple Silicon
Macs).

On Linux you'll want to supply either `--bundler linuxAppImage` or
`--bundler linuxRPM`, since the default Linux bundler (`linuxGeneric`) is
targeted at development and not distribution.

```sh
# Build the app. The result will be in `.build/bundler/apps/<YourApp>`
sbun bundle -c release
```

Add `--universal` when targeting macOS if you desire a universal build (i.e. a
build that runs on both arm64 and x86_64).

See <doc:bundlers> for information about available bundlers for each platform.

## Running the app from Xcode

Run the `generate-xcode-support` command if you want to use Xcode as your IDE.
This command only needs to be run once unless you delete the `.swiftpm`
directory.

```sh
# Creates the files necessary to get xcode to run the package as an app
sbun generate-xcode-support
```

To open the package in Xcode, just run `open Package.swift`, or use Finder to
open `Package.swift` with Xcode. To run the app, select the scheme with the
same name as your app and then click run.
