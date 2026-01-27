// swift-tools-version:6.0

import CompilerPluginSupport
import PackageDescription

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
    .package(url: "https://github.com/pointfreeco/swift-parsing", .upToNextMinor(from: "0.14.0")),
    .package(url: "https://github.com/stackotter/TOMLKit", from: "0.6.1"),
    .package(url: "https://github.com/onevcat/Rainbow", from: "4.0.0"),
    .package(url: "https://github.com/mxcl/Version", from: "2.0.0"),
    .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.0.0"),
    .package(url: "https://github.com/tuist/XcodeProj", from: "8.16.0"),
    .package(url: "https://github.com/yonaskolb/XcodeGen", from: "2.42.0"),
    .package(url: "https://github.com/swiftlang/swift-syntax", from: "601.0.1"),
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
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "SwiftASN1", package: "swift-asn1"),
        .product(name: "X509", package: "swift-certificates"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "Parsing", package: "swift-parsing"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        .product(name: "Overture", package: "swift-overture"),
        .product(name: "AsyncCollections", package: "async-collections"),
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
      resources: [
        .embedInCode("Resources/gradlew"),
        .embedInCode("Resources/gradle-wrapper.jar"),
        .embedInCode("Resources/DefaultAndroidIcon.webp"),
      ],
      swiftSettings: [
        .define("SUPPORT_HOT_RELOADING", .when(platforms: [.macOS, .linux])),
        .define("SUPPORT_XCODEPROJ", .when(platforms: [.macOS])),
        .swiftLanguageMode(.v5),
        .enableUpcomingFeature("FullTypedThrows"),
      ]
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

    .executableTarget(
      name: "schema-gen",
      dependencies: [
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax"),
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
  ]
)
