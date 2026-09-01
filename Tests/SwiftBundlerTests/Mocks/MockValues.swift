import Foundation
@testable import SwiftBundler

extension URL {
  init(forPackage package: String) {
    let identity = SwiftPackageManager.packageIdentity(forPackageWithName: package)
    self.init(fileURLWithPath: "/\(identity)")
  }
}

extension SwiftPackageManager.PackageSource {
  var url: URL {
    switch self {
      case .local(let url), .remote(let url):
        url
    }
  }
}

extension ConfigurationFlattener.Context {
  static var mock: Self {
    Self(
      platform: .macOS,
      bundler: .darwinApp,
      architectures: [.arm64]
    )
  }
}

extension SwiftPackageManager.Package {
  static func mock(
    name: String,
    identity: String? = nil,
    source: SwiftPackageManager.PackageSource? = nil,
    localCheckout: URL? = nil,
    dependencies: [Dependency] = [],
    traits: [SwiftPackageManager.Trait] = [],
    products: [SwiftPackageManager.Product] = [],
    targets: [SwiftPackageManager.Target] = [],
    fullConfiguration: PackageConfiguration? = nil,
    configuration: PackageConfiguration.Flat? = nil
  ) -> Self {
    let identity = identity ?? SwiftPackageManager.packageIdentity(forPackageWithName: name)
    let localCheckout = localCheckout ?? URL(forPackage: identity)
    return Self(
      name: name,
      identity: identity,
      source: source ?? .local(path: localCheckout),
      localCheckout: localCheckout,
      dependencies: dependencies,
      traits: traits,
      products: Dictionary(uniqueKeysWithValues: products.map { product in
        (product.name, product)
      }),
      targets: Dictionary(uniqueKeysWithValues: targets.map { target in
        var target = target
        let path = target.directory.path
          .replacingOccurrences(of: "<package>", with: localCheckout.path)
        target.directory = URL(fileURLWithPath: path)
        return (target.name, target)
      }),
      fullConfiguration: fullConfiguration,
      configuration: configuration
    )
  }
}

extension SwiftPackageManager.Target {
  static func mock(
    _ name: String,
    kind: Kind,
    directory: URL? = nil,
    dependencies: [SwiftPackageManager.TargetDependency] = []
  ) -> Self {
    Self(
      name: name,
      kind: kind,
      directory: directory ?? URL(fileURLWithPath: "<package>/Sources/\(name)"),
      dependencies: dependencies
    )
  }

  static func libraryMock(
    _ name: String,
    directory: URL? = nil,
    dependencies: [SwiftPackageManager.TargetDependency] = []
  ) -> Self {
    mock(name, kind: .library, directory: directory, dependencies: dependencies)
  }

  static func executableMock(
    _ name: String,
    directory: URL? = nil,
    dependencies: [SwiftPackageManager.TargetDependency] = []
  ) -> Self {
    mock(name, kind: .executable, directory: directory, dependencies: dependencies)
  }
}

extension SwiftPackageManager.TargetDependency {
  static func productMock(
    _ product: String,
    package: String? = nil,
    condition: SwiftPackageManager.TargetDependency.Condition? = nil
  ) -> Self {
    let package = package ?? product
    return .product(
      packageIdentity: SwiftPackageManager.packageIdentity(forPackageWithName: package),
      product: product,
      condition: condition
    )
  }
}

extension SwiftPackageManager.PackageDependency {
  static func mock(
    _ package: String,
    traits: Set<String> = [],
    location: PackageManifest.PackageDependency.Location? = nil
  ) -> Self {
    let reference = SwiftPackageManager.PackageReference(name: package)
    return Self(
      package: reference,
      traits: traits,
      location: location ?? .fileSystem(path: URL(forPackage: reference.identity))
    )
  }
}

extension SwiftPackageManager.Product {
  static func mock(
    _ name: String,
    productType: SwiftPackageManager.ProductType,
    targets: [String]? = nil
  ) -> Self {
    Self(name: name, productType: productType, targets: targets ?? [name])
  }

  static func libraryMock(
    _ name: String,
    targets: [String]? = nil
  ) -> Self {
    .mock(name, productType: .library(linkingType: .automatic), targets: targets)
  }

  static func executableMock(
    _ name: String,
    targets: [String]? = nil
  ) -> Self {
    .mock(name, productType: .executable, targets: targets)
  }
}

extension SwiftPackageManager.PackageReference: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self.init(name: value)
  }
}

extension SwiftPackageManager.TargetDependency.Condition {
  static func mock(
    platforms: [String] = [],
    traits: [String] = []
  ) -> Self {
    Self(platforms: platforms, traits: traits)
  }
}

extension SwiftPackageManager.Trait {
  static func mock(
    _ name: String,
    enabledTraits: [String] = []
  ) -> Self {
    Self(name: name, enabledTraits: enabledTraits)
  }
}

extension SwiftPackageManager.Trait: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self.init(name: value, enabledTraits: [])
  }
}
