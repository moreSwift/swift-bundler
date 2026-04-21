// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ProjectDemo",
    platforms: [.macOS(.v10_15)],
    dependencies: [
        // Our testing code ensures that Swift Bundler is present at the same location
        // when producing temporary copies of the fixture.
        .package(path: "../swift-bundler/"),
    ],
    targets: [
        .executableTarget(
            name: "ProjectDemo",
            dependencies: ["CLibHeaders"]
        ),
        .target(name: "CLibHeaders"),

        // MARK: Dev tools
        .executableTarget(
            name: "MakefileBuilder",
            dependencies: [
                .product(name: "SwiftBundlerBuilders", package: "swift-bundler"),
            ]
        )
    ]
)
