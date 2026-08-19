// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Traits",
    dependencies: [
        .package(path: "Library", traits: ["MyTrait"]),
    ],
    targets: [
        .executableTarget(
            name: "Traits",
            dependencies: ["Library"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
