import Foundation

extension SwiftPackageManager {
  /// A package's metadata and structure.
  struct Package<Dependency: Codable & Sendable>: Sendable {
    // IMPORTANT: Update Package.withReferences when new members are added to
    //   this struct (easy to miss if the members are optional).

    /// The package's name.
    var name: String
    /// The package's identity (either according to the package itself if
    /// loaded in isolation, or the root package if loaded as a dependency).
    var identity: String
    /// The package's original source.
    var source: PackageSource
    /// The package's local checkout. If it's a local dependency then this is
    /// just the path to the local dependency, otherwise it's a path to somewhere
    /// in `.build/checkouts`.
    var localCheckout: URL
    /// The package's dependencies.
    ///
    /// Sometimes we want to store rich dependency information (e.g. when
    /// loading packages in isolation), and sometimes we want to store
    /// references to dependencies loaded elsewhere (such as when storing
    /// packages in a ``PackageGraph``). That's why `Dependency` is a generic
    /// parameter.
    var dependencies: [Dependency]
    /// The package's products.
    var products: [String: Product]
    /// The package's targets.
    var targets: [String: Target]
    /// The package's full (i.e. not flattened) Swift Bundler configuration, if present.
    var fullConfiguration: PackageConfiguration?
    /// The package's Swift Bundler configuration flattened, if present.
    ///
    /// Excluded from Package's Codable implementation because it's not codable and the
    /// Codable implementation only exists for debugging purposes at the moment.
    var configuration: PackageConfiguration.Flat?

    /// A reference to the package in the context of its enclosing package graph.
    ///
    /// The validity of the reference is tied to the validity of the package's
    /// identity.
    var reference: PackageReference {
      PackageReference(identity: identity)
    }
  }
}

extension SwiftPackageManager.Package<PackageManifest.PackageDependency> {
  /// Converts a package that represents its dependencies by location into one
  /// that represents its dependencies by thin references.
  var withReferences: SwiftPackageManager.Package<SwiftPackageManager.PackageReference> {
    SwiftPackageManager.Package<SwiftPackageManager.PackageReference>(
      name: name,
      identity: identity,
      source: source,
      localCheckout: localCheckout,
      dependencies: dependencies.map(\.identity)
        .map(SwiftPackageManager.PackageReference.init(identity:)),
      products: products,
      targets: targets,
      fullConfiguration: fullConfiguration,
      configuration: configuration
    )
  }
}

extension SwiftPackageManager.Package: Codable {
  private enum CodingKeys: CodingKey {
    case name
    case identity
    case source
    case localCheckout
    case dependencies
    case products
    case targets
    case fullConfiguration
  }

  init(from decoder: any Decoder) throws {
    // Excludes `configuration` because it isn't codable (we only use this
    // codable implementation to display things for debugging)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    identity = try container.decode(String.self, forKey: .identity)
    source = try container.decode(SwiftPackageManager.PackageSource.self, forKey: .source)
    localCheckout = try container.decode(URL.self, forKey: .localCheckout)
    dependencies = try container.decode([Dependency].self, forKey: .dependencies)
    products = try container.decode([String: SwiftPackageManager.Product].self, forKey: .products)
    targets = try container.decode([String: SwiftPackageManager.Target].self, forKey: .targets)
    fullConfiguration = try container.decode(PackageConfiguration?.self, forKey: .fullConfiguration)
  }

  func encode(to encoder: any Encoder) throws {
    // Excludes `configuration` because it isn't codable (we only use this
    // codable implementation to display things for debugging)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(name, forKey: .name)
    try container.encode(identity, forKey: .identity)
    try container.encode(source, forKey: .source)
    try container.encode(localCheckout, forKey: .localCheckout)
    try container.encode(dependencies, forKey: .dependencies)
    try container.encode(products, forKey: .products)
    try container.encode(targets, forKey: .targets)
    try container.encode(fullConfiguration, forKey: .fullConfiguration)
  }
}
