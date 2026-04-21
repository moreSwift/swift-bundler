import Foundation
import Mutex

extension SwiftPackageManager {
  /// Shared mutable state used to coordinate the package graph loading process.
  private struct PackageGraphLoadingState: Sendable {
    var coveredDependencies: [PackageReference] = []
    var dependencyPackages: [PackageReference: Package<PackageReference>] = [:]
    var ignoredTransitiveDependencies: [PackageReference] = []
  }

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
    log.info("Resolving dependencies")
    try await SwiftPackageManager.resolveDependencies(
      packageDirectory: packageDirectory,
      toolchain: toolchain
    )

    log.info("Loading package graph")
    let checkoutsDirectory = packageDirectory / ".build/checkouts"
    let root = try await loadPackage(
      packageDirectory: packageDirectory,
      source: .local(path: packageDirectory),
      isRootPackage: true,
      configurationContext: configurationContext,
      toolchain: toolchain
    )

    let state = Mutex(PackageGraphLoadingState(
      // We initially process all root dependencies, so mark them as covered straight away.
      coveredDependencies: root.dependencies.map(\.identity).map(PackageReference.init(identity:)),
      dependencyPackages: [:],
      ignoredTransitiveDependencies: []
    ))

    // A wrapper around 'processDependency' to make callsites more succinct (using captures)
    let processDependency = { (dependency: PackageManifest.PackageDependency) async in
      return await Result.catching { () throws(Error) in
        try await Self.processDependency(
          dependency,
          state: state,
          packageDirectory: packageDirectory,
          checkoutsDirectory: checkoutsDirectory,
          configurationContext: configurationContext,
          toolchain: toolchain
        )
      }
    }

    let result: Result<(), Error> = await withTaskGroup(
      of: Result<[PackageManifest.PackageDependency], Error>.self
    ) { taskGroup in
      for dependency in root.dependencies {
        taskGroup.addTask {
          await processDependency(dependency)
        }
      }

      // Each dependency task can return transitive dependencies to process.
      // These dependencies have already been de-duplicated so all we have to
      // do here is queue them for processing.
      for await result in taskGroup {
        switch result {
          case .failure(let error):
            taskGroup.cancelAll()
            return .failure(error)
          case .success(let transitiveDependencies):
            for dependency in transitiveDependencies {
              taskGroup.addTask {
                await processDependency(dependency)
              }
            }
        }
      }

      return .success(())
    }
    try result.get()

    let finalState = state.withLock { $0 }
    return PackageGraph(
      rootPackage: root.withReferences,
      dependencyPackages: finalState.dependencyPackages,
      ignoredTransitiveDependencies: finalState.ignoredTransitiveDependencies
    )
  }

  /// Process a dependency as part of our parallelized TaskGroup-based package
  /// graph loading implementation.
  /// - Parameters:
  ///   - dependency: The dependency to load.
  ///   - state: Protected mutable state shared by all tasks in the task group.
  ///   - packageDirectory: The root directory of the root package of the package graph.
  ///   - checkoutsDirectory: The directory the SwiftPM stores package checkouts
  ///     for the root package of the package graph.
  ///   - configurationContext: Context used when loading Swift Bundler configuration
  ///     files contained within the dependency (if there are any).
  ///   - toolchain: The Swift toolchain to use when loading the dependency.
  private static func processDependency(
    _ dependency: PackageManifest.PackageDependency,
    state: borrowing Mutex<PackageGraphLoadingState>,
    packageDirectory: URL,
    checkoutsDirectory: URL,
    configurationContext: ConfigurationFlattener.Context,
    toolchain: URL?
  ) async throws(Error) -> [PackageManifest.PackageDependency] {
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

    // BEGIN: Slow section
    let package = try await loadPackage(
      packageDirectory: dependencyDirectory,
      source: source,
      identityOverride: dependency.identity,
      isRootPackage: false,
      configurationContext: configurationContext,
      toolchain: toolchain
    )
    // END: Slow section

    let reference = PackageReference(identity: package.identity)

    /// Determine transitive dependencies that are yet to be loaded and return
    /// them for further processing.
    var queuedDependencies: [PackageManifest.PackageDependency] = []
    state.withLock { state in
      state.dependencyPackages[reference] = package.withReferences

      for transitiveDependency in package.dependencies {
        // Make sure that we haven't covered this dependency yet
        let dependencyReference = PackageReference(identity: transitiveDependency.identity)
        guard
          !state.coveredDependencies.contains(
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
          ignoredTransitiveDependencies: &state.ignoredTransitiveDependencies
        )

        guard isUsed else {
          continue
        }

        state.coveredDependencies.append(dependencyReference)
        queuedDependencies.append(transitiveDependency)
      }
    }

    return queuedDependencies
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
