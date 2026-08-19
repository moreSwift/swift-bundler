// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "NestedDependency",
    products: [
        .library(
            name: "NestedDependency",
            targets: ["NestedDependency"]
        ),
    ],
    targets: [
        .target(
            name: "NestedDependency"
        ),
        .testTarget(
            name: "NestedDependencyTests",
        ),
    ],
    swiftLanguageModes: [.v6]
)
