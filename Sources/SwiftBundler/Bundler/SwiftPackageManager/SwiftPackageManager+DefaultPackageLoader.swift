import Foundation

extension SwiftPackageManager {
  /// The default package loader used by ``SwiftPackageManager``.
  struct DefaultPackageLoader: PackageLoader {
    func prepare(
      packageDirectory: URL,
      toolchain: URL?
    ) async throws(Error) {
      try await SwiftPackageManager.resolveDependencies(
        packageDirectory: packageDirectory,
        toolchain: toolchain
      )
    }

    func loadPackage(
      packageDirectory: URL,
      source: PackageSource,
      identityOverride: String?,
      isRootPackage: Bool,
      configurationContext: ConfigurationFlattener.Context,
      toolchain: URL?
    ) async throws(SwiftPackageManager.Error) -> Package<PackageDependency> {
      if source.isRemote && !packageDirectory.exists() {
        throw Error(.missingDependencyCheckout(packageDirectory))
      }

      let manifest = try await loadPackageManifest(from: packageDirectory, toolchain: toolchain)
      let partialManifest = try await loadPartialPackageDump(
        packageDirectory: packageDirectory,
        toolchain: toolchain
      )
      let packageName = manifest.name
      let packageIdentity = identityOverride ?? packageIdentity(forPackageWithName: packageName)

      let products = SwiftPackageManager.products(
        forManifest: manifest,
        partialManifest: partialManifest,
        isRootPackage: isRootPackage
      )

      let targets = SwiftPackageManager.targets(
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

      var traitsTable: [String: Set<String>] = [:]
      for dependency in partialManifest.dependencies {
        switch dependency {
          case .decoded(let identity, let traits, _):
            traitsTable[identity] = Set(traits)
          case .other:
            break
        }
      }

      var dependencies: [PackageDependency] = []
      for dependency in manifest.dependencies {
        dependencies.append(
          PackageDependency(
            package: PackageReference(identity: dependency.identity),
            traits: traitsTable[dependency.identity] ?? [],
            location: dependency.location
          )
        )
      }

      let traits = partialManifest.traits.map { trait in
        Trait(
          name: trait.name,
          description: trait.description,
          enabledTraits: trait.enabledTraits
        )
      }

      return Package(
        name: packageName,
        identity: packageIdentity,
        source: source,
        localCheckout: packageDirectory,
        dependencies: dependencies,
        traits: traits,
        products: products,
        targets: targets,
        fullConfiguration: fullConfiguration,
        configuration: configuration
      )
    }
  }
}
