import Foundation

extension SwiftPackageManager {
  // I know this function is horrid, I'm planning some refactoring but don't
  //   have the time right now. At least the function is naturally split into
  //   sections.
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

    var products: [String: Product] = [:]
    var targets: [String: Target] = [:]

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
        let partialCondition: PartialPackageDump.DependencyCondition?
        switch dependency {
          case .byName(_, let condition),
              .target(_, let condition),
              .product(_, _, let condition):
            partialCondition = condition
          case .unknown:
            log.warning(
              """
              Target '\(target.name)' in package '\(manifest.name)' has a \
              dependency that we failed to parse. Please open an issue at \
              \(SwiftBundler.newIssueURL), as this is likely due to a newer \
              Swift version breaking our parsing. Skipping dependency.
              """
            )
            continue
        }

        let condition: TargetDependency.Condition?
        switch partialCondition {
          case .platform(let names):
            condition = .platform(names: names)
          case .unknown:
            log.warning(
              """
              Target '\(target.name)' in package '\(manifest.name)' has a \
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
            let dependencyIdentity =
              targetDependencyPackageNameMap[dependencyPackageName.lowercased()]
          else {
            log.warning(
              """
              Could not find package dependency '\(dependencyPackageName)' referred \
              to by target '\(target.name)' in package '\(manifest.name)'.
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
                continue
              }

              targetDependencies.append(
                .product(
                  packageIdentity: dependencyIdentity,
                  product: dependencyName,
                  condition: condition
                )
              )
            } else {
              targetDependencies.append(.target(name: dependencyName, condition: condition))
            }
          case .target(let name, _):
            targetDependencies.append(.target(name: name, condition: condition))
          case .product(let dependencyPackage, let product, _):
            guard let dependencyIdentity = dependencyPackageIdentity(dependencyPackage) else {
              continue
            }

            targetDependencies.append(
              .product(
                packageIdentity: dependencyIdentity,
                product: product,
                condition: condition
              )
            )
          case .unknown:
            log.warning(
              """
              Target '\(target.name)' in package '\(manifest.name)' has a \
              dependency that we failed to parse. Please open an issue at \
              \(SwiftBundler.newIssueURL), as this is likely due to a newer \
              Swift version breaking our parsing. Skipping dependency.
              """
            )
            continue
        }
      }

      let kind: Target.Kind
      switch target.type {
        case .executable:
          kind = .executable
        case .library:
          kind = .library
        case .systemTarget:
          kind = .systemTarget
        case .test:
          kind = .test
        case .macro:
          kind = .macro
        case .plugin:
          kind = .plugin
        case .snippet:
          // We already ignore these further up
          continue
        case .other(let other):
          log.warning(
            """
            Target '\(target.name)' in package '\(manifest.name)' has unhandled \
            type '\(other)'. Please open an issue at \(SwiftBundler.newIssueURL), \
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
