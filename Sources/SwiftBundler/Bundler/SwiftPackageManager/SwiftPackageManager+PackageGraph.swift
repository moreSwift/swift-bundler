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

        let isUsed = dependencyIsPubliclyUsed(
          dependency: transitiveDependency,
          package: package
        )

        logDependency(
          dependencyReference,
          packageIdentity: package.identity,
          ignored: !isUsed,
          ignoredTransitiveDependencies: &ignoredTransitiveDependencies
        )

        guard isUsed else {
          continue
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

  /// Logs debug messages regarding our decision to ignore or load a given
  /// package dependency. Updates `ignoredTransitiveDependencies` (and uses
  /// it to avoid duplicate messages).
  private static func logDependency(
    _ dependencyReference: PackageReference,
    packageIdentity: String,
    ignored: Bool,
    ignoredTransitiveDependencies: inout [PackageReference]
  ) {
    if ignored {
      log.debug(
        """
        Ignoring transitive dependency '\(dependencyReference.identity)' \
        because '\(packageIdentity)' doesn't use it in any executable, \
        library, or systemTarget targets
        """
      )
      if !ignoredTransitiveDependencies.contains(dependencyReference) {
        ignoredTransitiveDependencies.append(dependencyReference)
      }
    } else {
      if ignoredTransitiveDependencies.contains(dependencyReference) {
        // We're not ignoring it anymore!
        log.debug(
          """
          Not ignoring transitive dependency '\(dependencyReference.identity)' \
          because '\(packageIdentity)' uses it in an executable, library, or \
          systemTarget target
          """
        )
        ignoredTransitiveDependencies.removeAll { $0 == dependencyReference }
      }
    }
  }

  /// Computes whether a given dependency is used publicly by a package. This aims
  /// to reproduce the logic used by SwiftPM to decide whether to include a given
  /// transitive dependency in package resolution or not.
  /// - Parameters:
  ///   - dependency: The dependency to check for usage of.
  ///   - package: The package to check for usage within.
  private static func dependencyIsPubliclyUsed(
    dependency: PackageManifest.PackageDependency,
    package: Package<PackageManifest.PackageDependency>
  ) -> Bool {
    // Only load a transitive dependency if it's used by a product, because
    // anything else gets counted as an internal detail by SwiftPM, which
    // leads to SwiftPM not checking out said dependency.
    return package.products.contains { productName, product in
      let productTargets = package.targets.filter { targetName, _ in
        product.targets.contains(targetName)
      }.values

      return productTargets.contains { target in
        target.dependencies.contains { targetDependency in
          switch targetDependency {
            case .product(let packageIdentity, _, _):
              dependency.identity == packageIdentity
            default:
              false
          }
        }
      }
    }
  }
}
