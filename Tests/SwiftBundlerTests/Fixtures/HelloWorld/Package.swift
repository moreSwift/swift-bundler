// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "HelloWorld",
    platforms: [.macOS(.v10_15)],
    targets: [
        .executableTarget(
            name: "HelloWorld"
        ),
    ]
)
