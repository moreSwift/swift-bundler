import Foundation

extension SwiftPackageManager {
  /// Loads the given package.
  /// - Parameters:
  ///   - packageDirectory: The root directory of the package to load.
  ///   - source: The original source of the package.
  ///   - identityOverride: The package's identity according to whichever package
  ///     is depending on this package (if any). If `nil` then the package's name
  ///     field is lowercased to obtain its identity according to itself.
  ///   - configurationContext: The context to use when flattening package configurations.
  ///   - toolchain: The Swift toolchain to use.
  /// - Returns: The loaded package.
  static func loadPackage( // swiftlint:disable:this cyclomatic_complexity
    packageDirectory: URL,
    source: PackageSource,
    identityOverride: String? = nil,
    isRootPackage: Bool,
    configurationContext: ConfigurationFlattener.Context,
    toolchain: URL?
  ) async throws(Error) -> Package<PackageManifest.PackageDependency> {
    let manifest = try await loadPackageManifest(from: packageDirectory, toolchain: toolchain)
    let partialManifest = try await loadPartialPackageDump(
      packageDirectory: packageDirectory,
      toolchain: toolchain
    )
    let packageName = manifest.name
    let packageIdentity = identityOverride ?? packageIdentity(forPackageWithName: packageName)

    let products = products(
      forManifest: manifest,
      partialManifest: partialManifest,
      isRootPackage: isRootPackage
    )

    let targets = targets(
      forManifest: manifest,
      partialManifest: partialManifest,
      products: products,
      packageName: packageName,
      packageIdentity: packageIdentity,
      packageDirectory: packageDirectory
    )

    // Load the package's bundler config file if present.
    let fullConfiguration: PackageConfiguration?
    let configuration: PackageConfiguration.Flat?
    if PackageConfiguration.standardConfigurationFileLocation(for: packageDirectory).exists() {
      let loadedConfiguration = try await Error.catch {
        try await PackageConfiguration.load(fromDirectory: packageDirectory)
      }
      fullConfiguration = loadedConfiguration
      configuration = try Error.catch {
        try ConfigurationFlattener.flatten(
          loadedConfiguration,
          with: configurationContext
        )
      }
    } else {
      fullConfiguration = nil
      configuration = nil
    }

    return Package(
      name: packageName,
      identity: packageIdentity,
      source: source,
      localCheckout: packageDirectory,
      dependencies: manifest.dependencies,
      products: products,
      targets: targets,
      fullConfiguration: fullConfiguration,
      configuration: configuration
    )
  }

  /// Parses out the targets from a package manifest and partial manifest dump.
  /// - Parameters:
  ///   - manifest: The package's manifest as loaded via the stable `swift package describe`
  ///     command.
  ///   - partialManifest: The package's manifest as loaded via the less stable
  ///     `swift package dump-package` command. We only load as much information
  ///     as we require to fully parse the package graph (to minimise the risk of
  ///     being affected by breaking changes to the output format).
  ///   - products: The products parsed from the manifest and partial manifest.
  ///   - packageName: Name to use for the package when resolving `.product`
  ///     target dependencies.
  ///   - packageIdentity: The package's identity in the package graph.
  ///   - packageDirectory: The root directory of the package.
  private static func targets(
    forManifest manifest: PackageManifest,
    partialManifest: PartialPackageDump,
    products: [String: Product],
    packageName: String,
    packageIdentity: String,
    packageDirectory: URL
  ) -> [String: Target] {
    var targets: [String: Target] = [:]

    let targetDependencyPackageNameMap = targetDependencyPackageNameMap(
      manifest: manifest,
      partialManifest: partialManifest,
      packageName: packageName,
      packageIdentity: packageIdentity
    )

    for target in manifest.targets {
      guard target.type != .snippet else {
        // We don't care about snippets at the moment, and we also don't parse
        // them in our partial manifest dumps
        continue
      }

      guard
        let partialTarget = partialManifest.targets.first(
          where: { $0.name == target.name }
        )
      else {
        // Usually we'd throw an error for this sort of failure, but we want this
        // code to be as resilient as possible against future Swift package manifest
        // format changes. If we just ignore problematic targets then we at least
        // have a chance of still parsing enough to be useful.
        log.warning(
          """
          Target '\(target.name)' in package '\(manifest.name)' is missing from \
          partial package manifest dump. Please open an issue at \
          \(SwiftBundler.newIssueURL), as this is likely due to a newer Swift \
          version breaking our parsing. Skipping target.
          """
        )
        log.debug("Available targets: \(partialManifest.targets.map(\.name))")
        continue
      }

      var targetDependencies: [TargetDependency] = []
      for dependency in partialTarget.dependencies {
        guard
          let targetDependency = parseTargetDependency(
            dependency,
            target: target,
            packageName: manifest.name,
            packageNameMap: targetDependencyPackageNameMap
          )
        else {
          continue
        }

        targetDependencies.append(targetDependency)
      }

      guard let kind = Target.Kind(from: target.type) else {
        log.warning(
          """
          Target '\(target.name)' in package '\(manifest.name)' has unhandled \
          type '\(target.type)'. Please open an issue at \(SwiftBundler.newIssueURL), \
          as this is likely due to a newer Swift version introducing a new target \
          type. Skipping target.
          """
        )
        continue
      }

      targets[target.name] = Target(
        name: target.name,
        kind: kind,
        directory: packageDirectory / target.path,
        dependencies: targetDependencies
      )
    }
    
    return targets
  }

  /// Pre-computes a map from package names to package identities. The map is used
  /// to resolve target dependencies on products.
  /// - Parameters:
  ///   - manifest: The package's manifest as loaded via the stable `swift package describe`
  ///     command.
  ///   - partialManifest: The package's manifest as loaded via the less stable
  ///     `swift package dump-package` command. We only load as much information
  ///     as we require to fully parse the package graph (to minimise the risk of
  ///     being affected by breaking changes to the output format).
  ///   - packageName: Name to use for the package when resolving `.product`
  ///     target dependencies.
  ///   - packageIdentity: The package's identity in the package graph.
  private static func targetDependencyPackageNameMap(
    manifest: PackageManifest,
    partialManifest: PartialPackageDump,
    packageName: String,
    packageIdentity: String
  ) -> [String: PackageReference] {
    // Maps from valid package names to use in `.product(name: _, package: <here>)`
    // syntax to package references. The keys are all lowercased and candidates
    // should be as well when indexing into the map. This is all because package
    // manifests allow custom package names to be defined for local dependencies,
    // and for remote git dependencies as well if you're using deprecated APIs.
    var targetDependencyPackageNameMap: [String: PackageReference] = [
      packageName.lowercased(): PackageReference(identity: packageIdentity)
    ]
    for dependency in manifest.dependencies {
      let resolutionName = partialManifest.dependencies.compactMap { partialDependency in
        switch partialDependency {
          case .decoded(let identity, .some(let resolutionName))
              where identity == dependency.identity:
            resolutionName
          default:
            nil
        }
      }.first

      let reference = PackageReference(identity: dependency.identity)
      let name = resolutionName?.lowercased() ?? dependency.identity
      targetDependencyPackageNameMap[name] = reference
    }
    return targetDependencyPackageNameMap
  }

  /// A description
  /// - Parameters:
  ///   - dependency: The dependency to parse.
  ///   - target: The target that the dependency came from.
  ///   - packageName: The name of the package that the dependency came from.
  ///   - packageNameMap: A map from package names to package identities.
  private static func parseTargetDependency(
    _ dependency: PartialPackageDump.TargetDependency,
    target: PackageManifest.Target,
    packageName: String,
    packageNameMap: [String: PackageReference]
  ) -> TargetDependency? {
    let partialCondition: PartialPackageDump.DependencyCondition?
    switch dependency {
      case .byName(_, let condition),
          .target(_, let condition),
          .product(_, _, let condition):
        partialCondition = condition
      case .unknown:
        log.warning(
          """
          Target '\(target.name)' in package '\(packageName)' has a \
          dependency that we failed to parse. Please open an issue at \
          \(SwiftBundler.newIssueURL), as this is likely due to a newer \
          Swift version breaking our parsing. Skipping dependency.
          """
        )
        return nil
    }

    let condition: TargetDependency.Condition?
    switch partialCondition {
      case .platform(let names):
        condition = .platform(names: names)
      case .unknown:
        log.warning(
          """
          Target '\(target.name)' in package '\(packageName)' has a \
          dependency condition that we failed to parse. Please open an issue at \
          \(SwiftBundler.newIssueURL), as this is likely due to a newer \
          Swift version breaking our parsing. Treating condition as \
          unconditionally true.
          """
        )
        condition = nil
      case .none:
        condition = nil
    }

    /// Gets the normalized package identity of the dependency with the
    /// given package name.
    func dependencyPackageIdentity(_ dependencyPackageName: String) -> String? {
      guard
        let dependencyIdentity = packageNameMap[dependencyPackageName.lowercased()]
      else {
        log.warning(
          """
          Could not find package dependency '\(dependencyPackageName)' referred \
          to by target '\(target.name)' in package '\(packageName)'.
          """
        )
        return nil
      }

      return dependencyIdentity.identity
    }

    switch dependency {
      case .byName(let dependencyName, _):
        if target.productDependencies?.contains(dependencyName) == true {
          guard let dependencyIdentity = dependencyPackageIdentity(dependencyName) else {
            return nil
          }

          return TargetDependency.product(
            packageIdentity: dependencyIdentity,
            product: dependencyName,
            condition: condition
          )
        } else {
          return TargetDependency.target(name: dependencyName, condition: condition)
        }
      case .target(let name, _):
        return TargetDependency.target(name: name, condition: condition)
      case .product(let dependencyPackage, let product, _):
        guard let dependencyIdentity = dependencyPackageIdentity(dependencyPackage) else {
          return nil
        }

        return TargetDependency.product(
          packageIdentity: dependencyIdentity,
          product: product,
          condition: condition
        )
      case .unknown:
        log.warning(
          """
          Target '\(target.name)' in package '\(packageName)' has a \
          dependency that we failed to parse. Please open an issue at \
          \(SwiftBundler.newIssueURL), as this is likely due to a newer \
          Swift version breaking our parsing. Skipping dependency.
          """
        )
        return nil
    }
  }

  /// Parses out products from the package's manifest and partial manifest dump.
  /// - Parameters:
  ///   - manifest: The package's manifest as loaded via the stable `swift package describe`
  ///     command.
  ///   - partialManifest: The package's manifest as loaded via the less stable
  ///     `swift package dump-package` command. We only load as much information
  ///   - isRootPackage: Whether the package is the root package in the package
  ///     graph. This affects whether we load 'implicit' executable products or not.
  private static func products(
    forManifest manifest: PackageManifest,
    partialManifest: PartialPackageDump,
    isRootPackage: Bool
  ) -> [String: Product] {
    var products: [String: Product] = [:]

    let explicitProducts = partialManifest.products.map(\.name)
    for product in manifest.products {
      guard isRootPackage || explicitProducts.contains(product.name) else {
        // We don't want to include synthetic executable products for non-root
        // packages, as that's what SwiftPM does as well
        continue
      }

      let productType: ProductType
      switch product.type {
        case .executable:
          productType = .executable
        case .plugin:
          productType = .plugin
        case .macro:
          productType = .macro
        case .snippet:
          // We don't care about snippets, for now
          continue
        case .library("automatic"):
          productType = .library(linkingType: .automatic)
        case .library("static"):
          productType = .library(linkingType: .static)
        case .library("dynamic"):
          productType = .library(linkingType: .dynamic)
        case .library(let unknownLinkingType):
          log.warning(
            """
            Library product '\(product.name)' has unhandled linking type \
            '\(unknownLinkingType)'. Please open an issue at \(SwiftBundler.newIssueURL)
            """
          )
          continue
        case .unknown:
          log.warning(
            """
            Product '\(product.name)' in package '\(manifest.name)' has unhandled \
            type. Please open an issue at \(SwiftBundler.newIssueURL)
            """
          )
          continue
      }

      products[product.name] = Product(
        name: product.name,
        productType: productType,
        targets: product.targets
      )
    }

    return products
  }

  /// Computes a package's identity from its name.
  ///
  /// This identity is only used within the package itself. Package identities
  /// of dependencies are generally determined from the package's git URL or
  /// path on disk rather than its self-declared name.
  /// - Parameter name: The package's name.
  /// - Returns: The package's identity according to itself.
  static func packageIdentity(forPackageWithName name: String) -> String {
    name.lowercased()
  }
}
