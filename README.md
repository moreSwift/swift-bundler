<p align="center">
  <img width="100%" src="banner.png">
</p>

<p align="center">
  <a href="https://swiftpackageindex.com/moreSwift/swift-bundler"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FmoreSwift%2Fswift-bundler%2Fbadge%3Ftype%3Dswift-versions"></a>
  <a href="https://github.com/moreSwift/swift-bundler/actions/workflows/swift-macos.yml" alt="Build macOS"><img src="https://github.com/moreSwift/swift-bundler/actions/workflows/swift-macos.yml/badge.svg"></a>
  <a href="https://github.com/moreSwift/swift-bundler/actions/workflows/swift-linux.yml" alt="Build Linux"><img src="https://github.com/moreSwift/swift-bundler/actions/workflows/swift-linux.yml/badge.svg"></a>
  <a href="https://github.com/moreSwift/swift-bundler/actions/workflows/swift-windows.yml" alt="Build Linux"><img src="https://github.com/moreSwift/swift-bundler/actions/workflows/swift-windows.yml/badge.svg"></a>
  <a href="https://moreswift.dev/discord"><img src="https://img.shields.io/discord/1123965445687484466?color=6A7EC2&label=discord&logo=discord&logoColor=ffffff"></a> 
</p>

<p align="center">
  An Xcodeproj-less tool for creating cross-platform Swift apps.
</p>

## Supporting Swift Bundler ❤️

If you find Swift Bundler useful, please consider supporting me by [becoming a sponsor](https://github.com/sponsors/stackotter). I spend most of my spare time working on open-source projects, and each sponsorship helps me focus more time on making high quality tools for the community.

## Documentation 📚

The documentation is hosted on [the Swift Bundler website](https://swiftbundler.dev/documentation/swift-bundler).

Join [the moreSwift Discord server](https://moreswift.dev/discord) if you have any questions.

## Installation 📦

Install the latest version of Swift Bundler with [mint](https://github.com/yonaskolb/Mint):

```sh
mint install stackotter/swift-bundler@main
```

See [Runtime dependencies](https://swiftbundler.dev/documentation/swift-bundler/installation#Runtime-dependencies) for a list of runtime dependencies and associated installation instructions.

If you have previously installed Swift Bundler via the installation script you must delete the `/opt/swift-bundler` directory (requires sudo).

For more installation methods, see [the documentation](https://swiftbundler.dev/documentation/swift-bundler/installation).

## Getting started 🚦

After installing Swift Bundler, package templates make it quick to get started. The following sections walk you through creating and running a simple 'Hello, World!' SwiftUI app.

### Creating a SwiftUI app

```sh
# Create a new app from the SwiftUI template.
swift bundler create HelloWorld --template SwiftUI
cd HelloWorld
```

### Running the app

```sh
# Build and run the app.
swift bundler run
```

### Using Xcode as your IDE

```sh
# Creates the files necessary to get xcode to run the package as an app.
# Only needs to be run once unless you delete the `.swiftpm` directory.
swift bundler generate-xcode-support

# Open the package in Xcode
open Package.swift
```

### Learning more

To learn more about Swift Bundler refer to the [documentation](https://swiftbundler.dev/documentation/swift-bundler).

## Contributing 🛠

Contributions of all kinds are very welcome! Just make sure to check out [the contributing guidelines](CONTRIBUTING.md) before getting started. Read through [the open issues](https://github.com/moreSwift/swift-bundler/issues) for contribution ideas.

Contributors generally discuss moreSwift development in [the moreSwift Discord server](https://moreswift.dev/discord); it's a great place to discuss contribution ideas or to get assistance with your contributions.

## Bug response policy 🐞

*Critical bugs will be addressed within 48 hours or less*. Critical bugs are classified as any bugs that risk loss of user/developer data or represent critical security vulnerabilities (around 8 or above on the CVSS scale as a rule of thumb, although Swift Bundler maintainers retain discretion).

Non-critical bugs will be addressed in order of priority with no strict turnaround commitments. As a general rule of thumb, we'll address security vulnerabilities, then bugs reported by sponsors, then any other bugs as time permits.

## Apps made with Swift Bundler 👨‍💻

If you have made an app with Swift Bundler, I'd love to hear about it! Just open an issue or submit a PR to add it to the list.

- [Delta Client](https://github.com/stackotter/delta-client): A 'Minecraft: Java Edition' compatible Minecraft client written from scratch in Swift (macOS only)
- [ModularMTL](https://github.com/JezewskiG/ModularMTL): A modular multiplication visualisation made with Swift Bundler, SwiftUI and Metal (macOS only)
- [Friend](https://github.com/JoshuaBrest/Friend): A technical demo that showcases how system-based assistants can be integrated with LLMs to provide greater flexibility and functionality (macOS only)
- [AutoDock](https://github.com/ghall89/AutoDock): A utility for automatically hiding and showing the macOS Dock based on connected display size. (macOS only)
- [Arcmark](https://github.com/Geek-1001/arcmark): A bookmark manager that attaches to any browser window as a sidebar. (macOS only)
