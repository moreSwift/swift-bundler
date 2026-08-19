import Foundation
import Mutex

extension SwiftPackageManager {
  /// Shared mutable state used to coordinate the package graph loading process.
  private struct PackageGraphLoadingState: Sendable {
    var coveredDependencies: Set<PackageReference> = []
    var enabledTraits: [PackageReference: Set<String>] = [:]
    var dependencyPackages: [PackageReference: Package<PackageDependency>] = [:]
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

    let toolchain = try await inferSwiftToolchain(
      toolchain,
      packageDirectory: packageDirectory
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
      coveredDependencies: [root.reference],
      enabledTraits: [root.reference: ["default"]],
      dependencyPackages: [:],
      ignoredTransitiveDependencies: []
    ))

    // A wrapper around 'processDependency' to make callsites more succinct (using captures)
    let processDependency = { (dependency: PackageDependency) async in
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
      of: Result<[PackageDependency], Error>.self
    ) { taskGroup in
      // Queue root dependencies (but only those that are used)
      taskGroup.addTask {
        await Result.catching { () throws(Error) in
          var queue: [PackageDependency] = []
          try state.withLock { (state) throws(Error) in
            try queueTransitiveDependencies(
              package: root,
              state: &state,
              into: &queue,
              requirePublicUsage: false
            )
          }
          return queue
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
      dependencyPackages: finalState.dependencyPackages.mapValues(\.withReferences),
      ignoredTransitiveDependencies: finalState.ignoredTransitiveDependencies,
      enabledTraits: finalState.enabledTraits
    )
  }

  /// Infers the Swift toolchain to use. Specifically, if the currently specified
  /// toolchain would result in Swiftly being invoked as a proxy then we query that
  /// Swiftly installation to discover the true path of the Swift toolchain being
  /// invoked. This lets us ignore '.swift-version' files present in the repositories
  /// of dependencies when dumping their package manifests.
  ///
  /// Even if the user specifies a toolchain, they could've technically specified a
  /// directory containing symlinks to swiftly, so we might as well cover that case
  /// too (given that the logic won't affect anyone who isn't symlinking to swiftly).
  /// - Parameter toolchain: The toolchain argument provided by the user (if any).
  /// - Parameter packageDirectory: The root directory of the root package of the
  ///   package graph. We let the '.swift-version' of that directory influence our
  ///   inference (if it exists).
  private static func inferSwiftToolchain(
    _ toolchain: URL?,
    packageDirectory: URL
  ) async throws(Error) -> URL? {
    let swiftExecutablePath = try await Error.catch {
      if let toolchain {
        return swiftPath(toolchain: toolchain)
      } else {
        return try await Process.locate("swift")
      }
    }

    let swiftExecutable = URL(fileURLWithPath: swiftExecutablePath)
      .actuallyResolvingSymlinksInPath()

    let inferredToolchain: URL?
    if swiftExecutable.lastPathComponent == "swiftly" {
      let swiftlyExecutable = swiftExecutable
      let actualSwiftPath = try await Error.catch {
        try await Process.create(
          swiftlyExecutable.path,
          arguments: ["run", "which", "swift"],
          directory: packageDirectory
        ).getOutput().trimmingCharacters(in: .whitespacesAndNewlines)
      }

      inferredToolchain = URL(fileURLWithPath: actualSwiftPath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    } else {
      inferredToolchain = toolchain
    }

    return inferredToolchain
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
    _ dependency: PackageDependency,
    state: borrowing Mutex<PackageGraphLoadingState>,
    packageDirectory: URL,
    checkoutsDirectory: URL,
    configurationContext: ConfigurationFlattener.Context,
    toolchain: URL?
  ) async throws(Error) -> [PackageDependency] {
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
      identityOverride: dependency.package.identity,
      isRootPackage: false,
      configurationContext: configurationContext,
      toolchain: toolchain
    )
    // END: Slow section

    state.withLock { state in
      // We've only just loaded the package, so any existing traits in
      // state.enabledTraits won't have been recursively evaluated yet.
      // We take care to recursively evaluate the whole union of traits
      // rather than just those passed in from the particular dependency
      // edge that got us here.
      let enabledTraits = package.recursivelyEnabledTraits(
        enabledTraits: Set(dependency.traits)
          .union(state.enabledTraits[dependency.package] ?? [])
      )
      state.enabledTraits[dependency.package] = enabledTraits
    }

    var queuedDependencies: [PackageDependency] = []
    try state.withLock { state throws(Error) in
      try queueTransitiveDependencies(
        package: package,
        state: &state,
        into: &queuedDependencies
      )
    }
    return queuedDependencies
  }

  private static func queueTransitiveDependencies(
    package: Package<PackageDependency>,
    state: inout PackageGraphLoadingState,
    into queuedDependencies: inout [PackageDependency],
    requirePublicUsage: Bool = true
  ) throws(Error) {
    let reference = PackageReference(identity: package.identity)

    let enabledTraits = package.recursivelyEnabledTraits(
      enabledTraits: state.enabledTraits[reference] ?? []
    )

    /// Determine transitive dependencies that are yet to be loaded and return
    /// them for further processing.
    state.dependencyPackages[reference] = package

    for transitiveDependency in package.dependencies {
      // Make sure that we haven't covered this dependency yet
      let dependencyReference = transitiveDependency.package

      guard !state.coveredDependencies.contains(dependencyReference) else {
        if let dependencyPackage = state.dependencyPackages[dependencyReference] {
          // The package has already been loaded, so we have to check whether this
          // dependency edge contains any new traits that haven't been enabled yet
          let enabledDependencyTraits = Set(dependencyPackage.recursivelyEnabledTraits(
            enabledTraits: transitiveDependency.traits
          ))

          // The package has been loaded, so the state.enabledTraits entry for this
          // package has already been recursively evaluated; we can just subtract them
          // to get the set of new traits.
          let containsNewTraits = !enabledDependencyTraits.subtracting(
            state.enabledTraits[dependencyReference] ?? []
          ).isEmpty

          state.enabledTraits[dependencyReference, default: []].formUnion(enabledDependencyTraits)
          if containsNewTraits, let dependencyPackage = state.dependencyPackages[reference] {
            // If we discovered more traits, we must attempt requeue the package's
            // dependencies recursively as new dependencies may have been enabled,
            // and new traits may have been passed on to the dependency's own
            // dependencies
            try queueTransitiveDependencies(
              package: dependencyPackage,
              state: &state,
              into: &queuedDependencies
            )
          }
        } else {
          // We can't compute the set of all traits recursively enabled yet,
          // because we haven't loaded the package, so we just store them in
          // the look up table and they will get evaluated properly when the
          // package gets loaded
          state.enabledTraits[dependencyReference, default: []]
            .formUnion(transitiveDependency.traits)
        }
        
        continue
      }

      let isUsed = try dependencyIsUsed(
        dependency: transitiveDependency,
        package: package,
        enabledTraits: enabledTraits,
        onlyCountPublicUsage: requirePublicUsage
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

      state.coveredDependencies.insert(dependencyReference)
      queuedDependencies.append(transitiveDependency)
    }
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

  /// Computes whether a given dependency is used by a package. This aims
  /// to reproduce the logic used by SwiftPM to decide whether to include a given
  /// transitive dependency in package resolution or not.
  /// - Parameters:
  ///   - dependency: The dependency to check for usage of.
  ///   - package: The package to check for usage within.
  ///   - enabledTraits: The set of traits enabled for the package to check for
  ///     usage within.
  ///   - onlyCountPublicUsage: When resolving dependencies of a non-root package,
  ///     only publicly used dependencies get checked out. This parameter emulates
  ///     that behavior.
  private static func dependencyIsUsed(
    dependency: PackageDependency,
    package: Package<PackageDependency>,
    enabledTraits: Set<String>,
    onlyCountPublicUsage: Bool
  ) throws(Error) -> Bool {
    var queue: [Target]
    if onlyCountPublicUsage {
      // Only load a transitive dependency if it's used by a product, because
      // anything else gets counted as an internal detail by SwiftPM, which
      // leads to SwiftPM not checking out said dependency.
      let directlyUsedTargets = package.products
        .filter { _, product in
          switch product.productType {
            case .executable, .library:
              return true
            case .macro, .plugin:
              return false
          }
        }
        .flatMap(\.value.targets)

      queue = Array(
        package.targets.filter { targetName, _ in
          directlyUsedTargets.contains(targetName)
        }.values
      )
    } else {
      queue = Array(package.targets.values)
    }

    var seen = Set(queue.map(\.name))

    while let target = queue.popLast() {
      for targetDependency in target.dependencies {
        switch targetDependency {
          case .product(let packageIdentity, _, let condition):
            guard condition?.traitClauseIsSatisfied(by: enabledTraits) ?? true else {
              continue
            }

            if dependency.package.identity == packageIdentity {
              return true
            }
          case .target(let targetName, let condition):
            if seen.insert(targetName).inserted {
              guard let target = package.targets[targetName] else {
                throw Error(.targetNotFoundInPackage(targetName, package.reference))
              }

              guard condition?.traitClauseIsSatisfied(by: enabledTraits) ?? true else {
                continue
              }

              switch target.kind {
                case .library, .executable, .systemTarget:
                  break
                case .binary, .macro, .plugin, .snippet, .test:
                  continue
              }

              queue.append(target)
            }
        }
      }
    }

    return false
  }
}
