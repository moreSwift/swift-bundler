// swift-tools-version:6.0

import CompilerPluginSupport
import Foundation
import PackageDescription

// ## Compile-time environment options
//
// - SBUN_NO_SCHEMA_GEN : Disables the schema-gen target which depends on
//     swift-syntax and effectively ruins swift-syntax prebuilts even when
//     we're building unrelated targets. Used to speed up CI release builds.

let env = ProcessInfo.processInfo.environment
let schemaGenTargets: [Target]
if env["SBUN_NO_SCHEMA_GEN"] == "1" {
  schemaGenTargets = [
    .executableTarget(
      name: "schema-gen",
      dependencies: [
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    )
  ]
} else {
  schemaGenTargets = []
}

let package = Package(
  name: "swift-bundler",
  platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .macCatalyst(.v13)],
  products: [
    .executable(name: "swift-bundler", targets: ["swift-bundler"]),
    .library(name: "SwiftBundler", targets: ["SwiftBundler"]),
    .library(name: "SwiftBundlerRuntime", targets: ["SwiftBundlerRuntime"]),
    .library(name: "SwiftBundlerBuilders", targets: ["SwiftBundlerBuilders"]),
    .plugin(name: "SwiftBundlerCommandPlugin", targets: ["SwiftBundlerCommandPlugin"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    .package(url: "https://github.com/apple/swift-log", from: "1.5.4"),
    // This fork removes the dependency on swift-syntax (which was used for
    // features we don't use) to speed up Swift Bundler release builds
    .package(url: "https://github.com/stackotter/swift-parsing", .upToNextMinor(from: "0.15.0")),
    .package(url: "https://github.com/stackotter/TOMLKit", from: "0.7.0"),
    .package(url: "https://github.com/onevcat/Rainbow", from: "4.0.0"),
    .package(url: "https://github.com/mxcl/Version", from: "2.0.0"),
    .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.0.0"),
    .package(url: "https://github.com/tuist/XcodeProj", from: "8.16.0"),
    .package(url: "https://github.com/yonaskolb/XcodeGen", from: "2.42.0"),
    .package(url: "https://github.com/swiftlang/swift-syntax", from: "601.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-overture", from: "0.5.0"),
    .package(url: "https://github.com/swhitty/FlyingFox", from: "0.22.0"),
    .package(url: "https://github.com/jpsim/Yams", from: "5.1.2"),
    .package(url: "https://github.com/kylef/PathKit", from: "1.0.1"),
    .package(url: "https://github.com/apple/swift-certificates", from: "1.7.0"),
    .package(url: "https://github.com/apple/swift-asn1", from: "1.1.0"),
    .package(url: "https://github.com/apple/swift-crypto", from: "3.10.0"),
    .package(url: "https://github.com/CoreOffice/XMLCoder", from: "0.17.1"),
    .package(url: "https://github.com/adam-fowler/async-collections.git", from: "0.1.0"),
    .package(url: "https://github.com/gregcotten/AsyncProcess", from: "0.0.5"),
    .package(url: "https://github.com/stackotter/ErrorKit", from: "1.2.2"),
    .package(
      url: "https://github.com/stackotter/swift-macro-toolkit",
      .upToNextMinor(from: "0.7.1")
    ),
    .package(url: "https://github.com/swhitty/swift-mutex", .upToNextMinor(from: "0.0.6")),
    .package(url: "https://github.com/stackotter/swift-ico", .upToNextMinor(from: "0.2.0")),
    .package(
      url: "https://github.com/stackotter/swift-image-formats",
      .upToNextMinor(from: "0.5.0")
    ),
    .package(
      url: "https://github.com/gregcotten/ZIPFoundationModern",
      .upToNextMinor(from: "0.0.5")
    ),

    // File watcher dependencies
    .package(url: "https://github.com/sersoft-gmbh/swift-inotify", "0.4.0"..<"0.5.0"),
    .package(url: "https://github.com/apple/swift-system", from: "1.2.0"),
    .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.3"),
  ],
  targets: [
    .executableTarget(name: "swift-bundler", dependencies: ["SwiftBundler"]),
    .target(
      name: "SwiftBundler",
      dependencies: [
        "SwiftBundlerBuilders",
        "SwiftBundlerMacrosPlugin",
        "ErrorKit",
        "Rainbow",
        "TOMLKit",
        "Version",
        "XMLCoder",
        "Yams",
        "SwiftSyntaxUtils",
        .product(name: "ZIPFoundation", package: "ZIPFoundationModern"),
        .product(name: "Ico", package: "swift-ico"),
        .product(name: "ImageFormats", package: "swift-image-formats"),
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "SwiftASN1", package: "swift-asn1"),
        .product(name: "X509", package: "swift-certificates"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "Parsing", package: "swift-parsing"),
        .product(name: "Overture", package: "swift-overture"),
        .product(name: "AsyncCollections", package: "async-collections"),
        .product(name: "Mutex", package: "swift-mutex"),
        .product(
          name: "ProcessSpawnSync",
          package: "AsyncProcess",
          condition: .when(platforms: [.linux])
        ),

        // Xcodeproj related dependencies
        .product(
          name: "XcodeProj",
          package: "XcodeProj",
          condition: .when(platforms: [.macOS])
        ),
        .product(
          name: "PathKit",
          package: "PathKit",
          condition: .when(platforms: [.macOS])
        ),
        .product(
          name: "XcodeGenKit",
          package: "XcodeGen",
          condition: .when(platforms: [.macOS])
        ),
        .product(
          name: "ProjectSpec",
          package: "XcodeGen",
          condition: .when(platforms: [.macOS])
        ),

        // Hot reloading related dependencies
        .product(
          name: "FlyingSocks",
          package: "FlyingFox",
          condition: .when(platforms: [.macOS, .linux])
        ),
        .target(
          name: "HotReloadingProtocol",
          condition: .when(platforms: [.macOS, .linux])
        ),
        .target(
          name: "FileSystemWatcher",
          condition: .when(platforms: [.macOS, .linux])
        ),
      ],
      swiftSettings: [
        .define("SUPPORT_HOT_RELOADING", .when(platforms: [.macOS, .linux])),
        .define("SUPPORT_XCODEPROJ", .when(platforms: [.macOS])),
        .swiftLanguageMode(.v5),
        .enableUpcomingFeature("FullTypedThrows"),
      ]
    ),

    // Code taken from SwiftSyntax to avoid needing to build the entirety of
    // Swift Syntax when building Swift Bundler. Licensed under Apache 2.0;
    // see Sources/SwiftSyntaxUtils/LICENSE.txt
    .target(
      name: "SwiftSyntaxUtils",
      exclude: ["LICENSE.txt"]
    ),

    .macro(
      name: "SwiftBundlerMacrosPlugin",
      dependencies: [
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "MacroToolkit", package: "swift-macro-toolkit"),
      ]
    ),

    .target(
      name: "SwiftBundlerRuntime",
      dependencies: [
        .product(name: "FlyingSocks", package: "FlyingFox"),
        "HotReloadingProtocol",
        "SwiftBundlerRuntimeC",
      ]
    ),
    .target(name: "SwiftBundlerRuntimeC"),

    .target(
      name: "SwiftBundlerBuilders",
      dependencies: [
        .product(
          name: "ProcessSpawnSync",
          package: "AsyncProcess",
          condition: .when(platforms: [.linux])
        )
      ]
    ),

    .target(
      name: "HotReloadingProtocol",
      dependencies: [
        .product(name: "FlyingSocks", package: "FlyingFox")
      ]
    ),

    .target(
      name: "FileSystemWatcher",
      dependencies: [
        .product(
          name: "Inotify",
          package: "swift-inotify",
          condition: .when(platforms: [.linux])
        ),
        .product(
          name: "SystemPackage",
          package: "swift-system",
          condition: .when(platforms: [.linux])
        ),
        .product(
          name: "AsyncAlgorithms",
          package: "swift-async-algorithms",
          condition: .when(platforms: [.linux])
        ),
      ]
    ),

    .testTarget(
      name: "SwiftBundlerTests",
      dependencies: ["SwiftBundler"],
      resources: [
        .copy("Fixtures")
      ]
    ),

    .plugin(
      name: "SwiftBundlerCommandPlugin",
      capability: .command(
        intent: .custom(
          verb: "bundler",
          description: "Run a package as an app."
        ),
        permissions: [
          .writeToPackageDirectory(
            reason: "Creating an app bundle requires writing to the package directory.")
        ]
      ),
      dependencies: [
        .target(name: "swift-bundler")
      ]
    ),
  ] + schemaGenTargets
)
