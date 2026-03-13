// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Library",
    products: [
        .library(
            name: "Library",
            targets: ["Library"]
        ),
        .executable(
            name: "LibraryHelper",
            targets: ["LibraryHelper"]
        ),
    ],
    targets: [
        .target(name: "Library"),
        .executableTarget(name: "LibraryHelper"),
    ]
)
