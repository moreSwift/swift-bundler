// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Library",
    products: [
        .library(
            name: "Library",
            targets: ["Library"]
        ),
    ],
    traits: [
        .trait(
            name: "MyTrait",
            description: "Extra features"
        ),
        .default(enabledTraits: []),
    ],
    dependencies: [
        .package(path: "NestedDependency"),
    ],
    targets: [
        .target(
            name: "Library",
            dependencies: [
                .product(
                    name: "NestedDependency",
                    package: "NestedDependency",
                    condition: .when(traits: ["MyTrait"])
                ),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
