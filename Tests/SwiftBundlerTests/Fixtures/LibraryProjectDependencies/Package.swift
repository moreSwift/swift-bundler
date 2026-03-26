// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "LibraryProjectDependencies",
    platforms: [.macOS(.v10_15)],
    dependencies: [
        .package(path: "Library"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: ["Library"]
        ),
    ]
)
