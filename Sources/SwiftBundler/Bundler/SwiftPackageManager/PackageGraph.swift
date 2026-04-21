extension SwiftPackageManager {
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
}
