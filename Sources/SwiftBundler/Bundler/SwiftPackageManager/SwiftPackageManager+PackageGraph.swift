import Foundation

extension SwiftPackageManager {
  /// Loads the given package and all of its dependencies into a package graph.
  ///
  /// It's best to call this on a root package (rather than a package checkout)
  /// because it will populate `<packageDirectory>/.build/checkouts` if not
  /// already present.
  /// - Parameters:
  ///   - packageDirectory: The root directory of the package to load.
  ///   - toolchain: The Swift toolchain to use.
  ///   - configurationContext: The context to use when flattening package configurations.
  /// - Returns: A package graph containing the root package and all of its
  ///   dependencies.
  static func loadPackageGraph(
    packageDirectory: URL,
    configurationContext: ConfigurationFlattener.Context,
    toolchain: URL?
  ) async throws(Error) -> PackageGraph {
    try await SwiftPackageManager.resolveDependencies(
      packageDirectory: packageDirectory,
      toolchain: toolchain
    )

    let checkoutsDirectory = packageDirectory / ".build/checkouts"
    let root = try await loadPackage(
      packageDirectory: packageDirectory,
      source: .local(path: packageDirectory),
      isRootPackage: true,
      configurationContext: configurationContext,
      toolchain: toolchain
    )

    var remainingDependencies = root.dependencies
    var dependencyPackages: [PackageReference: Package<PackageReference>] = [:]
    var ignoredTransitiveDependencies: [PackageReference] = []
    while let dependency = remainingDependencies.popLast() {
      let dependencyDirectory = dependency.localCheckout(
        packageDirectory: packageDirectory,
        checkoutsDirectory: checkoutsDirectory
      )

      if dependency.location.isRemote && !dependencyDirectory.exists() {
        throw Error(.missingDependencyCheckout(dependencyDirectory))
      }

      let source = switch dependency.location {
        case .fileSystem(let path): PackageSource.local(path: path)
        case .sourceControl(let url): PackageSource.remote(gitRepository: url)
      }

      let package = try await loadPackage(
        packageDirectory: dependencyDirectory,
        source: source,
        identityOverride: dependency.identity,
        isRootPackage: false,
        configurationContext: configurationContext,
        toolchain: toolchain
      )
      let reference = PackageReference(identity: package.identity)
      dependencyPackages[reference] = package.withReferences

      for transitiveDependency in package.dependencies {
        // Make sure that we haven't loaded this dependency yet and aren't already queued to
        let dependencyReference = PackageReference(identity: transitiveDependency.identity)
        guard
          !dependencyPackages.keys.contains(dependencyReference),
          !remainingDependencies.contains(
            where: { $0.identity == transitiveDependency.identity
          })
        else {
          continue
        }

        // Only load a transitive dependency if it's used by a product, because
        // anything else gets counted as an internal detail by SwiftPM, which
        // leads to SwiftPM not checking out said dependency.
        let isUsed = package.products.contains { productName, product in
          let productTargets = package.targets.filter { targetName, _ in
            product.targets.contains(targetName)
          }.values

          return productTargets.contains { target in
            target.dependencies.contains { targetDependency in
              switch targetDependency {
                case .product(let packageIdentity, _, _):
                  transitiveDependency.identity == packageIdentity
                default:
                  false
              }
            }
          }
        }

        guard isUsed else {
          log.debug(
            """
            Ignoring transitive dependency '\(transitiveDependency.identity)' \
            because '\(package.identity)' doesn't use it in any executable, \
            library, or systemTarget targets
            """
          )
          if !ignoredTransitiveDependencies.contains(dependencyReference) {
            ignoredTransitiveDependencies.append(dependencyReference)
          }
          continue
        }

        if ignoredTransitiveDependencies.contains(dependencyReference) {
          // We're not ignoring it anymore!
          log.debug(
            """
            Not ignoring transitive dependency '\(transitiveDependency.identity)' \
            because '\(package.identity)' uses it in an executable, library, or \
            systemTarget target
            """
          )
          ignoredTransitiveDependencies.removeAll { $0 == dependencyReference }
        }

        remainingDependencies.append(transitiveDependency)
      }
    }

    return PackageGraph(
      rootPackage: root.withReferences,
      dependencyPackages: dependencyPackages,
      ignoredTransitiveDependencies: ignoredTransitiveDependencies
    )
  }

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
  private static func loadPackage( // swiftlint:disable:this cyclomatic_complexity
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
  private static func packageIdentity(forPackageWithName name: String) -> String {
    name.lowercased()
  }

  /// A package graph containing a root package and all of its identities.
  struct PackageGraph: Codable, Sendable {
    /// The root package.
    var rootPackage: Package<PackageReference>
    /// The root package's dependencies (including transitive ones).
    var dependencyPackages: [PackageReference: Package<PackageReference>]
    /// Transitive dependencies that we intentionally ignored when loading this
    /// package graph. Used to produce helpful diagnostics.
    var ignoredTransitiveDependencies: [PackageReference]

    /// Gets the package referred to by the given package reference.
    /// - Parameter packageReference: The package reference.
    /// - Throws: If the package cannot be found.
    /// - Returns: The package.
    func package(
      referredToBy packageReference: PackageReference
    ) throws(Error) -> Package<PackageReference> {
      if rootPackage.reference == packageReference {
        return rootPackage
      } else if let dependency = dependencyPackages[packageReference] {
        return dependency
      } else if ignoredTransitiveDependencies.contains(packageReference) {
        throw Error(.packageIntentionallyExcludedFromPackageGraph(packageReference))
      } else {
        let identities = [rootPackage.identity] + Array(dependencyPackages.keys)
        log.debug("Available package identities: \(identities)")
        throw Error(.packageNotFoundInGraph(packageReference))
      }
    }

    /// Gets the target referred to by the given target reference.
    /// - Parameter targetReference: The target reference.
    /// - Throws: If the package cannot be found or does not contain such a target.
    /// - Returns: The target.
    func target(
      referredToBy targetReference: TargetReference
    ) throws(Error) -> Target {
      let package = try package(referredToBy: targetReference.package)
      guard let target = package.targets[targetReference.name] else {
        throw Error(.targetNotFoundInPackage(targetReference.name, targetReference.package))
      }
      return target
    }

    /// Gets the Swift Bundler configuration of the given package, if it has any.
    /// - Parameter packageReference: The package to get the configuration of.
    /// - Throws: If the package cannot be found.
    /// - Returns: The package's configuration if it has any, otherwise `nil`.
    func configuration(
      ofPackage packageReference: PackageReference
    ) throws(Error) -> PackageConfiguration.Flat? {
      let package = try package(referredToBy: packageReference)
      return package.configuration
    }

    /// Gets the Swift Bundler configuration of the given target, if it has any.
    /// - Parameter targetReference: The target to get the configuration of.
    /// - Throws: If the target's package cannot be found.
    /// - Returns: The target's configuration if it has any, otherwise `nil`.
    func configuration(
      ofTarget targetReference: TargetReference
    ) throws(Error) -> TargetConfiguration.Flat? {
      let packageConfiguration = try configuration(ofPackage: targetReference.package)
      return packageConfiguration?.targets[targetReference.name]
    }

    /// Gets all products within the package graph. Uses the assumption that
    /// each product name appears at most once.
    ///
    /// This relies on potentially undocumented SwiftPM behaviour so it should
    /// remain internal even if we make the rest of this API public. That is,
    /// we assume that each product name appears at most once. We make that
    /// assumption because if we don't make that assumption then there's still
    /// nothing that we can do differently in our product handling due to SwiftPM
    /// not allowing you to disambiguate products when building them from the
    /// command line.
    internal func allProducts() -> [String: Product] {
      // blame is used when producing duplicate product name warnings
      var blame: [String: PackageReference] = [:]

      var allProducts = rootPackage.products
      for name in rootPackage.products.keys {
        blame[name] = rootPackage.reference
      }

      for package in dependencyPackages.values {
        for (name, product) in package.products {
          if allProducts.keys.contains(name) {
            log.warning(
              """
              Both '\(blame[name]?.identity ?? "<unknown>")' and '\(package.reference)' \
              contain a product named '\(name)'. Leaving this unresolved may cause \
              issues with SwiftPM if both products are executable products and \
              you include one of them as a helper executable. More specifically, \
              SwiftPM cannot build executable products within the root package \
              if there's an identically-named product present in a dependency package
              """
            )
            log.warning(
              """
              """
            )
          }
          allProducts[name] = product
          blame[name] = package.reference
        }
      }

      return allProducts
    }

    /// Gets the product with the given name from the package graph.
    ///
    /// This relies on potentially undocumented SwiftPM behaviour so it should
    /// remain internal even if we make the rest of this API public. That is,
    /// we assume that each product name appears at most once. We make that
    /// assumption because if we don't make that assumption then there's still
    /// nothing that we can do differently in our product handling due to SwiftPM
    /// not allowing you to disambiguate products when building them from the
    /// command line.
    internal func product(named name: String) throws(Error) -> Product {
      guard let product = allProducts()[name] else {
        throw Error(.productNotFoundInGraph(name))
      }
      return product
    }

    /// Gets the targets directly contained within a product.
    /// - Parameters:
    ///   - product: The product to get the targets of.
    ///   - packageReference: The package containing the product.
    /// - Throws: If the given package or product cannot be found.
    /// - Returns: The product's targets.
    func targets(
      ofProduct product: String,
      inPackage packageReference: PackageReference
    ) throws(Error) -> [TargetReference] {
      let package = try self.package(referredToBy: packageReference)

      if let product = package.products[product] {
        return product.targets.map { target in
          TargetReference(name: target, package: packageReference)
        }
      } else if let target = package.targets[product], target.kind == .executable {
        // Support implicit executable products
        return [TargetReference(name: product, package: packageReference)]
      } else {
        throw Error(.productNotFoundInPackage(product, packageReference))
      }
    }

    /// Gets the targets contained both directly and transitively within a
    /// product.
    ///
    /// Excludes macro and plugin dependencies, as the code from those does
    /// not end up in the final executable, which is all that Swift Bundler
    /// cares about.
    /// - Parameters:
    ///   - product: The product to get transitive targets of.
    ///   - packageReference: The package containing the product.
    /// - Throws: If any required packages, products, or targets cannot be found.
    /// - Returns: The targets contained within the product both directly and
    ///   transitively.
    func transitiveTargets(
      inProduct product: String,
      inPackage packageReference: PackageReference
    ) throws(Error) -> [ConditionalTargetReference] {
      let directTargets = try targets(
        ofProduct: product,
        inPackage: packageReference
      )

      let indirectTargets = try directTargets.flatMap { (target) throws(Error) in
        return try transitiveTargetDependencies(
          ofTarget: target.name,
          inPackage: target.package
        )
      }

      let targets = directTargets.map { target in
        ConditionalTargetReference(target: target, conditions: [])
      } + indirectTargets

      return targets.uniqued()
    }

    /// Gets the target references, from a collection of conditional target
    /// references, that are active when targeting the given platform.
    /// - Parameters:
    ///   - references: A collection of conditional target references.
    ///   - targetPlatform: The target platform to evaluate conditions against.
    /// - Returns: The active target references.
    func activeTargets(
      inConditionalReferences references: [ConditionalTargetReference],
      withTargetPlatform targetPlatform: Platform
    ) -> [TargetReference] {
      references.compactMap { reference in
        let conditionsSatisfied = reference.conditions.allSatisfy { condition in
          condition.isSatisfied(targetPlatform: targetPlatform)
        }

        if conditionsSatisfied {
          return reference.target
        } else {
          return nil
        }
      }.uniqued()
    }

    /// Gets the direct and transitive dependencies of the given target; i.e.
    /// all targets that the given target depends on either directly or
    /// indirectly.
    ///
    /// The same target may appear twice, but only with different conditions.
    ///
    /// Excludes macro and plugin dependencies, as the code from those does
    /// not end up in the final executable, which is all that Swift Bundler
    /// cares about.
    func transitiveTargetDependencies(
      ofTarget target: String,
      inPackage packageReference: PackageReference
    ) throws(Error) -> [ConditionalTargetReference] {
      let directDependencies = try directTargetDependencies(
        ofTarget: target,
        inPackage: packageReference
      )

      var remainingDependencies = directDependencies
      var dependencies: [ConditionalTargetReference] = directDependencies

      while let dependency = remainingDependencies.popLast() {
        let nestedDirectDependencies = try directTargetDependencies(
          ofTarget: dependency.target.name,
          inPackage: dependency.target.package
        ).map { dependency in
          dependency.appendingConditions(dependency.conditions)
        }

        for dependency in nestedDirectDependencies {
          guard !dependencies.contains(dependency) else {
            continue
          }

          remainingDependencies.append(dependency)
          dependencies.append(dependency)
        }
      }

      return dependencies
    }

    /// Gets all direct dependencies of the given target; i.e. targets that
    /// the given target declares as depencencies, and the targets contained
    /// within each prdouct that the target declares as a dependency.
    ///
    /// Excludes macro and plugin dependencies, as the code from those does
    /// not end up in the final executable, which is all that Swift Bundler
    /// cares about.
    func directTargetDependencies(
      ofTarget target: String,
      inPackage packageReference: PackageReference
    ) throws(Error) -> [ConditionalTargetReference] {
      let package = try self.package(referredToBy: packageReference)

      guard let target = package.targets[target] else {
        throw Error(.targetNotFoundInPackage(target, packageReference))
      }
      
      return try target.dependencies.flatMap { (dependency) throws(Error) in
        switch dependency {
          case .target(let name, let condition):
            let targetReference = ConditionalTargetReference(
              target: TargetReference(name: name, package: packageReference),
              conditions: [condition].compactMap { $0 }
            )

            // Exclude macro and plugin targets as we're only interested in targets with
            // code that ends up in the final executable.
            let dependencyTarget = try self.target(referredToBy: targetReference.target)
            if dependencyTarget.kind == .macro || dependencyTarget.kind == .plugin {
              return []
            }

            return [targetReference]
          case .product(let packageIdentity, let product, let condition):
            let dependencyPackageReference = PackageReference(identity: packageIdentity)
            return try targets(
              ofProduct: product,
              inPackage: dependencyPackageReference
            ).map { target in
              ConditionalTargetReference(
                target: target,
                conditions: [condition].compactMap { $0 }
              )
            }
        }
      }
    }
  }

  /// A conditional reference to a target.
  struct ConditionalTargetReference: Sendable, Hashable {
    /// A reference to the underlying target.
    var target: TargetReference
    /// A condition which dictates when this reference should be counted as
    /// active. No conditions implies that the reference is unconditional.
    var conditions: [TargetDependency.Condition]

    /// Gets the reference with the given conditions appended to its existing
    /// conditions.
    func appendingConditions(_ conditions: [TargetDependency.Condition]) -> Self {
      var reference = self
      reference.conditions += conditions
      return reference
    }
  }

  /// A reference to a target in a package graph.
  struct TargetReference: Sendable, Hashable, CustomStringConvertible {
    /// The name of the target.
    var name: String
    /// A reference to the target's enclosing package.
    var package: PackageReference

    var description: String {
      "\(package.identity).\(name)"
    }
  }

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

  /// A package's original source.
  enum PackageSource: Codable, Sendable {
    /// A package loaded from a local path.
    case local(path: URL)
    /// A package loaded from a remote git repository.
    case remote(gitRepository: URL)
  }

  /// A reference to a unique package.
  struct PackageReference: Codable, Sendable, Hashable, CustomStringConvertible {
    /// The package's identity.
    var identity: String

    /// Creates a package reference from a package identity.
    init(identity: String) {
      self.identity = identity
    }

    /// Creates a package reference from a package name. This reference
    /// may only be valid within the package itself, as the identity of
    /// a package can change depending on how it was depended upon.
    init(name: String) {
      self.identity = packageIdentity(forPackageWithName: name)
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      self.init(identity: try container.decode(String.self))
    }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(identity)
    }

    var description: String {
      identity
    }
  }

  /// A package product.
  struct Product: Codable, Sendable {
    /// The product's name.
    var name: String
    /// The product's type.
    var productType: ProductType
    /// The product's targets.
    var targets: [String]
  }

  /// The type of a product.
  enum ProductType: Codable, Sendable, Hashable {
    /// An executable product.
    case executable
    /// A library product.
    case library(linkingType: LinkingType)
    /// A plugin product.
    case plugin
    /// A macro product.
    case macro
  }

  /// The linking type of a library product.
  enum LinkingType: String, Codable, Sendable, Hashable {
    /// The default linking type. SwiftPM adapts the linking of the product to
    /// the context of the build.
    case automatic
    /// The library gets built as a static library.
    case `static`
    /// The library gets built as a dynamic library.
    case dynamic
  }

  /// A package target.
  struct Target: Codable, Sendable {
    /// The target's name.
    var name: String
    /// The kind of target.
    var kind: Kind
    /// The directory containing the target's sources.
    var directory: URL
    /// The target's dependency.
    var dependencies: [TargetDependency]

    /// The kind of a target.
    enum Kind: String, Codable, Sendable, Hashable {
      /// A library target.
      case library
      /// An executable target.
      case executable
      /// A system target.
      case systemTarget
      /// A test target.
      case test
      /// A macro target.
      case macro
      /// A plugin target.
      case plugin
    }
  }

  /// A dependency of a package target.
  enum TargetDependency: Codable, Sendable, Hashable {
    /// A dependency on another target within the same package.
    case target(name: String, condition: Condition?)
    /// A dependency on a product within the same package or a dependency of the package.
    case product(packageIdentity: String, product: String, condition: Condition?)

    /// A condition that must be satisfied for a target dependency to be active.
    enum Condition: Codable, Sendable, Hashable {
      /// A condition that's only active when the target platform is contained
      /// within `names`.
      case platform(names: [String])

      /// Gets whether the condition is satisfied when targeting the given platform.
      /// - Parameter targetPlatform: The target platform.
      /// - Returns: Whether the condition is satisfied.
      func isSatisfied(targetPlatform: Platform) -> Bool {
        switch self {
          case .platform(let names):
            names.contains(targetPlatform.os.manifestConditionName)
        }
      }
    }
  }

  /// Loads a package's package manifest via the 'swift package dump-package'
  /// command. It only loads precisely the information required by other Swift
  /// Bundler methods in order to minimise the risk of a future format changing
  /// breaking Swift Bundler. It also attempts to return a partial result when it
  /// encounters unexpected data, rather than failing entirely, leading to more
  /// graceful degradation when broken by a format change or edge case.
  private static func loadPartialPackageDump(
    packageDirectory: URL,
    toolchain: URL?
  ) async throws(Error) -> PartialPackageDump {
    let process = Process.create(
      swiftPath(toolchain: toolchain),
      arguments: ["package", "dump-package"],
      directory: packageDirectory
    )

    let output = try await Error.catch {
      try await process.getOutputData(excludeStdError: true)
    }

    return try Error.catch {
      try JSONDecoder().decode(PartialPackageDump.self, from: output)
    }
  }

  /// A partial represenation of the output of 'swift package dump-package'. See
  /// ``Self/loadPartialPackageDump(packageDirectory:toolchain:)`` for more.
  private struct PartialPackageDump: Sendable, Decodable {
    var dependencies: [Dependency]
    var products: [Product]
    var targets: [Target]

    /// A Partial decoding of package dependencies. We only need this for
    /// associating the `nameForTargetDependencyResolutionOnly` values with
    /// identities, so that's all we parse.
    enum Dependency: Sendable, Decodable {
      case decoded(
        identity: String,
        nameForTargetDependencyResolutionOnly: String?
      )
      case other

      enum CodingKeys: String, CodingKey {
        case fileSystem
        case sourceControl
      }

      struct DTO: Decodable {
        var identity: String
        var nameForTargetDependencyResolutionOnly: String?
      }

      init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Only fileSystem and sourceControl dependencies can have the
        // nameForTargetDependencyResolutionOnly field afaict, so we
        // ignore other dependencies.
        let key: CodingKeys
        if container.contains(.fileSystem) {
          key = .fileSystem
        } else if container.contains(.sourceControl) {
          key = .sourceControl
        } else {
          self = .other
          return
        }

        // Why did SwiftPM have to make this format so strange... I've done my
        // best to describe the error concisely, but I don't think there's really
        // any good description
        let dtos = try container.decode([DTO].self, forKey: key)
        guard let dto = dtos.first else {
          throw DecodingError.dataCorrupted(DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: "Expected at least one entry in dependency encoding, found none"
          ))
        }

        if dtos.count > 1 {
          // It seems extremely unlikely that we'd manage to decode both entries as
          // DTO values if they added an extra entry to the array, but might as well
          // warn about it just in case
          log.warning(
            """
            Expected a single dependency DTO, found multiple. Please report this \
            at \(SwiftBundler.newIssueURL)
            """
          )
        }

        self = .decoded(
          identity: dto.identity,
          nameForTargetDependencyResolutionOnly:
            dto.nameForTargetDependencyResolutionOnly
        )
      }
    }

    /// We only need the product names from the partial package dump (to detect
    /// which products are explicit and which have been synthesized).
    struct Product: Sendable, Decodable {
      var name: String
    }

    struct Target: Sendable, Decodable {
      var name: String
      var dependencies: [TargetDependency]
    }

    enum DependencyCondition: Sendable, Decodable {
      case platform(names: [String])
      case unknown

      enum CodingKeys: String, CodingKey {
        case platformNames
      }

      init(from decoder: any Decoder) throws {
        do {
          let container = try decoder.container(keyedBy: CodingKeys.self)
          let platformNames = try container.decode([String].self, forKey: .platformNames)
          self = .platform(names: platformNames)
        } catch {
          log.warning(
            """
            Failed to parse Swift target dependency condition, skipping. Please \
            open an issue at \(SwiftBundler.newIssueURL). Cause: \
            \(error.localizedDescription)
            """
          )
          self = .unknown
        }
      }
    }

    enum TargetDependency: Sendable, Decodable {
      case byName(String, DependencyCondition?)
      case target(String, DependencyCondition?)
      case product(package: String, product: String, DependencyCondition?)
      case unknown

      enum CodingKeys: String, CodingKey {
        case byName
        case target
        case product
      }

      struct ByName: Sendable, Decodable {
        var name: String
        var condition: DependencyCondition?

        init(from decoder: any Decoder) throws {
          var container = try decoder.unkeyedContainer()
          name = try container.decode(String.self)
          condition = try container.decode(DependencyCondition?.self)
        }
      }

      struct Product: Sendable, Decodable {
        var package: String
        var product: String
        var condition: DependencyCondition?

        init(from decoder: any Decoder) throws {
          var container = try decoder.unkeyedContainer()
          product = try container.decode(String.self)
          package = try container.decode(String.self)
          // Skip module aliases
          _ = try container.decode([String: String]?.self)
          condition = try container.decode(DependencyCondition?.self)
        }
      }

      init(from decoder: any Decoder) throws {
        do {
          let container = try decoder.container(keyedBy: CodingKeys.self)
        
          if container.allKeys.contains(.byName) {
            let dependency = try container.decode(ByName.self, forKey: .byName)
            self = .byName(dependency.name, dependency.condition)
          } else if container.allKeys.contains(.target) {
            let dependency = try container.decode(ByName.self, forKey: .target)
            self = .target(dependency.name, dependency.condition)
          } else {
            let dependency = try container.decode(Product.self, forKey: .product)
            self = .product(
              package: dependency.package,
              product: dependency.product,
              dependency.condition
            )
          }
        } catch {
          log.warning(
            """
            Failed to parse Swift target dependency, skipping. Please open an \
            issue at \(SwiftBundler.newIssueURL). Cause: \
            \(error.localizedDescription)
            """
          )
          self = .unknown
        }
      }
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
