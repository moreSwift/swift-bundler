import AsyncCollections
import Foundation
import SwiftBundlerBuilders
import Version
import ErrorKit

enum ProjectBuilder {
  struct BuiltProduct {
    var product: ProjectConfiguration.Product.Flat
    var artifacts: [Artifact]
  }

  struct Artifact {
    var location: URL
  }

  /// A reference to a dependency, along with the depender who caused the dependency.
  struct DependencyReference: Hashable, Sendable, CustomStringConvertible {
    /// The entity that caused the dependency. Multiple entities can depend on the
    /// one product, but a dependency reference is a particular instance of that
    /// product.
    var depender: Depender
    /// The product being depended upon.
    var product: ProductReference

    /// A reference to the project containing the product.
    var project: ProjectReference {
      product.project
    }

    /// A reference to the package containing the project.
    var package: SwiftPackageManager.PackageReference {
      project.package
    }

    var description: String {
      let base = product.description
      switch depender {
        case .app:
          return base
        case .target(let depender):
          return "\(base) required by target \(depender)"
      }
    }
  }

  /// The entity that directly depends upon a given dependency.
  enum Depender: Hashable, Sendable {
    /// The root app being built
    case app
    /// A target being built as part of the app
    case target(SwiftPackageManager.TargetReference)
  }

  /// A reference to a Swift Bundler sub-project.
  struct ProjectReference: Codable, Hashable, Sendable {
    /// The name of the project.
    var name: String
    /// The package containing the project.
    var package: SwiftPackageManager.PackageReference
  }

  /// A reference to a project product (either a SwiftPM product or a subproject
  /// product).
  struct ProductReference: Hashable, Sendable, CustomStringConvertible {
    /// The project containing the product.
    var project: ProjectReference
    /// The product's name.
    var name: String

    /// The package containing the project.
    var package: SwiftPackageManager.PackageReference {
      project.package
    }

    var description: String {
      "\(package).\(project.name).\(name)"
    }
  }

  static func buildDependencies(
    appConfiguration: AppConfiguration.Flat,
    packageConfiguration: PackageConfiguration.Flat,
    packageGraph: SwiftPackageManager.PackageGraph,
    context: GenericBuildContext,
    swiftToolchain: URL?,
    appName: String,
    dryRun: Bool
  ) async throws(Error) -> [ProductReference: BuiltProduct] {
    let dependencies = try enumerateDependencies(
      appConfiguration: appConfiguration,
      packageGraph: packageGraph,
      targetPlatform: context.platform
    )

    var builtProjects: Set<ProjectReference> = []
    var builtProducts: [ProductReference: BuiltProduct] = [:]
    for dependency in dependencies {
      try await buildDependency(
        dependency,
        packageConfiguration: packageConfiguration,
        packageGraph: packageGraph,
        context: context,
        swiftToolchain: swiftToolchain,
        appName: appName,
        dryRun: dryRun,
        builtProjects: &builtProjects,
        builtProducts: &builtProducts
      )
    }

    return builtProducts
  }

  private static func enumerateDependencies(
    appConfiguration: AppConfiguration.Flat,
    packageGraph: SwiftPackageManager.PackageGraph,
    targetPlatform: Platform
  ) throws(Error) -> [DependencyReference] {
    var dependencies: [DependencyReference] = []

    func processDependencies(
      _ dependencyConfigs: [AppConfiguration.Dependency],
      depender: Depender
    ) {
      let package = switch depender {
        case .app: packageGraph.rootPackage.reference
        case .target(let target): target.package
      }
      for dependency in dependencyConfigs {
        dependencies.append(
          DependencyReference(
            depender: depender,
            product: ProductReference(
              project: ProjectReference(
                name: dependency.project,
                package: package
              ),
              name: dependency.product
            )
          )
        )
      }
    }

    processDependencies(appConfiguration.dependencies, depender: .app)

    let targets = try Error.catch {
      let targets = try packageGraph.transitiveTargets(
        inProduct: appConfiguration.product,
        inPackage: packageGraph.rootPackage.reference
      )
      return packageGraph.activeTargets(
        inConditionalReferences: targets,
        withTargetPlatform: targetPlatform
      )
    }

    for target in targets {
      let configuration = try Error.catch {
        try packageGraph.configuration(ofTarget: target)
      }
      guard let configuration else { continue }

      processDependencies(configuration.dependencies, depender: .target(target))
    }

    return dependencies
  }

  private static func project(
    referredToBy projectReference: ProjectReference,
    packageGraph: SwiftPackageManager.PackageGraph
  ) throws(Error) -> ProjectConfiguration.Flat {
    let configuration = try Error.catch {
      try packageGraph.configuration(ofPackage: projectReference.package)
    }

    guard let configuration else {
      throw Error(.noSuchProject(projectReference))
    }

    guard let project = configuration.projects[projectReference.name] else {
      throw Error(.noSuchProject(projectReference))
    }

    return project
  }

  private static func buildDependency(
    _ dependency: DependencyReference,
    packageConfiguration: PackageConfiguration.Flat,
    packageGraph: SwiftPackageManager.PackageGraph,
    context: GenericBuildContext,
    swiftToolchain: URL?,
    appName: String,
    dryRun: Bool,
    builtProjects: inout Set<ProjectReference>,
    builtProducts: inout [ProductReference: BuiltProduct]
  ) async throws(Error) {
    let projectName = dependency.project.name

    // Special case the root project (just use SwiftPM)
    if dependency.project.name == ProjectConfiguration.rootProjectName {
      if !dryRun {
        log.info(
          """
          Building product '\(dependency.product.name)' from package \
          '\(dependency.package)'
          """
        )
      }

      let builtProduct = try await buildRootProjectProduct(
        dependency.product.name,
        package: dependency.package,
        packageGraph: packageGraph,
        context: context,
        swiftToolchain: swiftToolchain,
        dryRun: dryRun
      )
      builtProducts[dependency.product] = builtProduct
      return
    }

    let project = try project(
      referredToBy: dependency.project,
      packageGraph: packageGraph
    )

    guard let product = project.products[dependency.product.name] else {
      throw Error(.noSuchProduct(dependency))
    }

    let projectScratchDirectory = ScratchDirectoryStructure(
      scratchDirectory: context.scratchDirectory / projectName
    )

    let productsDirectoryExists =
      projectScratchDirectory.products.exists(withType: .directory)

    let requiresBuilding = !builtProjects.contains(dependency.project)
    builtProjects.insert(dependency.project)

    let productPath = product.artifactPath(
      whenNamed: dependency.product.name,
      platform: context.platform
    )
    let auxiliaryArtifactPaths = product.auxiliaryArtifactPaths(
      whenNamed: dependency.product.name,
      platform: context.platform
    )

    if requiresBuilding && !dryRun {
      // Set up required directories and build whole project
      log.info("Building project '\(projectName)'")
      if productsDirectoryExists {
        try Error.catch {
          try FileManager.default.removeItem(at: projectScratchDirectory.products)
        }
      }

      try projectScratchDirectory.createRequiredDirectories()

      do {
        try await ProjectBuilder.buildProject(
          projectName,
          configuration: project,
          builders: packageConfiguration.builders,
          packageDirectory: context.projectDirectory,
          scratchDirectory: projectScratchDirectory,
          swiftToolchain: swiftToolchain
        )
      } catch {
        throw Error(.failedToBuildProject(name: projectName), cause: error)
      }
    }

    if !dryRun {
      log.info("Copying product '\(dependency)'")
    }

    let artifactPaths = [productPath] + auxiliaryArtifactPaths
    let artifacts = try artifactPaths.compactMap { (path) throws(Error) -> Artifact? in
      let builtProduct = projectScratchDirectory.build / path
      return try copyArtifact(
        builtProduct,
        to: projectScratchDirectory.products,
        isRequired: path == productPath,
        product: dependency.product.name,
        dryRun: dryRun
      )
    }

    let builtProduct = BuiltProduct(product: product, artifacts: artifacts)
    builtProducts[dependency.product] = builtProduct
  }

  /// Attempts to copy the given artifact to the given directory. If the artifact
  /// isn't required and doesn't exist then we return `nil`. For required but
  /// missing artifacts, an error is thrown.
  static func copyArtifact(
    _ builtArtifact: URL,
    to directory: URL,
    isRequired: Bool,
    product: String,
    dryRun: Bool
  ) throws(Error) -> Artifact? {
    // Ensure that the artifact either exists or is not required.
    guard builtArtifact.exists() || !isRequired else {
      let message = ErrorMessage.missingProductArtifact(
        builtArtifact,
        product: product
      )
      throw Error(message)
    }

    // Copy the artifact if present and not a dry run, then report it if
    // it exists.
    let destination = directory / builtArtifact.lastPathComponent
    if !dryRun && builtArtifact.exists() {
      try FileManager.default.copyItem(
        at: builtArtifact,
        to: destination,
        errorMessage: ErrorMessage.failedToCopyProduct
      )
    }

    if builtArtifact.exists() {
      return Artifact(location: destination)
    } else {
      return nil
    }
  }

  /// Builds the specified product from the root project (a.k.a. the root SwiftPM
  /// package). This is used to build products directly contained within the root
  /// package, and also products of dependencies of the root package. This works
  /// because SwiftPM generally expects products to have unique names (it runs
  /// into errors when they don't, so we're safe to assume people won't let product
  /// names clash).
  ///
  /// We could do this better by specifically targeting the directory of the
  /// package checkout directly containing the product, but that would come with
  /// the downside of requiring a separate `.build` directory for each project we
  /// build a product from (leading to increased disk space usage). It also wouldn't
  /// change our behaviour, because when there are duplicate product names the product
  /// in the external package is the one that gets used (from my testing), meaning that
  /// we'd still be unable to build non-uniquely named products directly contained
  /// within the root package.
  ///
  /// Note that when building products from dependency packages (rather than the
  /// root package) we can only build explicit products (not implicit executable
  /// products).
  static func buildRootProjectProduct(
    _ productName: String,
    package: SwiftPackageManager.PackageReference,
    packageGraph: SwiftPackageManager.PackageGraph,
    context: GenericBuildContext,
    swiftToolchain: URL?,
    dryRun: Bool
  ) async throws(Error) -> BuiltProduct {
    // Locate product in manifest
    let product: SwiftPackageManager.Product
    do {
      product = try packageGraph.product(named: productName)
    } catch {
      throw Error(.noSuchRootProjectProduct(package: package, product: productName))
    }

    // We only support 'helper executable'-style dependencies for SwiftPM products at the moment
    guard product.productType == .executable else {
      let message = ErrorMessage.unsupportedRootProjectProductType(
        product.productType,
        product: productName
      )
      throw Error(message)
    }

    // Build product
    let buildContext = SwiftPackageManager.BuildContext(
      genericContext: context,
      toolchain: swiftToolchain,
      hotReloadingEnabled: false,
      isGUIExecutable: false
    )

    let productsDirectory: URL
    do {
      if !dryRun {
        try await SwiftPackageManager.build(
          product: productName,
          buildContext: buildContext
        )
      }

      productsDirectory = try await SwiftPackageManager.getProductsDirectory(
        buildContext
      )
    } catch {
      throw Error(.failedToBuildRootProjectProduct(name: productName), cause: error)
    }

    // Produce built product description
    let productConfiguration = ProjectConfiguration.Product.Flat(
      type: .executable,
      outputDirectory: nil
    )
    let artifactPath = productConfiguration.artifactPath(
      whenNamed: productName,
      platform: context.platform
    )
    let artifacts = [
      ProjectBuilder.Artifact(location: productsDirectory / artifactPath)
    ]
    let builtProduct = BuiltProduct(product: productConfiguration, artifacts: artifacts)

    return builtProduct
  }

  static func checkoutSource(
    _ source: ProjectConfiguration.Source.Flat,
    at destination: URL,
    packageDirectory: URL
  ) async throws(Error) {
    let destinationExists = (try? destination.checkResourceIsReachable()) == true
    switch source {
      case .git(let url, let requirement):
        try await checkoutGitSource(
          destination: destination,
          destinationExists: destinationExists,
          repository: url,
          requirement: requirement
        )
      case .local(let path):
        try await checkoutLocalSource(
          destination: destination,
          destinationExists: destinationExists,
          packageDirectory: packageDirectory,
          path: path
        )
    }
  }

  static func checkoutGitSource(
    destination: URL,
    destinationExists: Bool,
    repository: URL,
    requirement: ProjectConfiguration.APIRequirement
  ) async throws(Error) {
    do {
      let currentURL = try await Error.catch {
        try await Git.getRemoteURL(destination, remote: "origin")
      }

      guard currentURL.absoluteString == repository.absoluteString else {
        throw Error(.mismatchedGitURL(currentURL, expected: repository))
      }
    } catch {
      if destinationExists {
        try Error.catch {
          try FileManager.default.removeItem(at: destination)
        }
      }

      try await Error.catch {
        try await Git.clone(repository, to: destination)
      }
    }

    let revision: String
    switch requirement {
      case .revision(let value):
        revision = value
    }

    try await Error.catch {
      try await Process.create(
        "git",
        arguments: ["checkout", revision],
        directory: destination
      ).runAndWait()
    }
  }


  static func checkoutLocalSource(
    destination: URL,
    destinationExists: Bool,
    packageDirectory: URL,
    path: String
  ) async throws(Error) {
    if destinationExists {
      try Error.catch {
        try FileManager.default.removeItem(at: destination)
      }
    }

    let source = packageDirectory / path
    guard source.exists() else {
      throw Error(.invalidLocalSource(source))
    }

    try Error.catch {
      try FileManager.default.createSymlink(
        at: destination,
        withRelativeDestination: source.path(
          relativeTo: destination.deletingLastPathComponent()
        )
      )
    }
  }

  struct OnDiskBuilder {
    var name: String
    var product: String
    var packageRoot: URL
  }

  static func prepareBuilder(
    _ builder: ProjectConfiguration.Builder.Flat,
    builders: [String: BuilderConfiguration.Flat],
    packageDirectory: URL,
    scratchDirectory: ScratchDirectoryStructure,
    swiftToolchain: URL?
  ) async throws(Error) -> OnDiskBuilder {
    switch builder {
      case .inline(let inlineBuilder):
        return try await prepareInlineBuilder(
          forInlineBuilder: inlineBuilder,
          packageDirectory: packageDirectory,
          scratchDirectory: scratchDirectory,
          swiftToolchain: swiftToolchain
        )
      case .named(let name):
        guard let builderConfiguration = builders[name] else {
          throw Error(.noSuchBuilder(name, Array(builders.keys)))
        }

        // Just sitting here to raise alarms when more kinds are added
        switch builderConfiguration.kind {
          case .wholeProject:
            break
        }

        return OnDiskBuilder(
          name: name,
          product: builderConfiguration.product,
          packageRoot: packageDirectory
        )
    }
  }

  /// Builds a project and returns the directory containing the built
  /// products on success.
  static func buildProject(
    _ name: String,
    configuration: ProjectConfiguration.Flat,
    builders: [String: BuilderConfiguration.Flat],
    packageDirectory: URL,
    scratchDirectory: ScratchDirectoryStructure,
    swiftToolchain: URL?
  ) async throws(Error) {
    try await checkoutSource(
      configuration.source,
      at: scratchDirectory.sources,
      packageDirectory: packageDirectory
    )

    let builder = try await prepareBuilder(
      configuration.builder,
      builders: builders,
      packageDirectory: packageDirectory,
      scratchDirectory: scratchDirectory,
      swiftToolchain: swiftToolchain
    )

    let builtBuilder = try await buildBuilder(
      builder,
      scratchDirectory: scratchDirectory,
      swiftToolchain: swiftToolchain
    )

    try await runBuilder(
      builtBuilder,
      for: configuration,
      scratchDirectory: scratchDirectory
    )
  }

  static func buildBuilder(
    _ builder: OnDiskBuilder,
    scratchDirectory: ScratchDirectoryStructure,
    swiftToolchain: URL?
  ) async throws(Error) -> URL {
    // Build the builder
    let buildContext = SwiftPackageManager.BuildContext(
      genericContext: GenericBuildContext(
        projectDirectory: builder.packageRoot,
        scratchDirectory: builder.packageRoot / ".build",
        configuration: .debug,
        architectures: [.host],
        platform: HostPlatform.hostPlatform.platform,
        additionalArguments: []
      ),
      toolchain: swiftToolchain,
      isGUIExecutable: false
    )

    let productsDirectory: URL
    do {
      try await SwiftPackageManager.build(
        product: builder.product,
        buildContext: buildContext
      )

      productsDirectory = try await SwiftPackageManager.getProductsDirectory(buildContext)
    } catch {
      throw Error(.failedToBuildBuilder(name: builder.name), cause: error)
    }

    let builderFileName = HostPlatform.hostPlatform
      .executableFileName(forBaseName: builder.product)
    let builder = productsDirectory / builderFileName
    return builder
  }

  static func runBuilder(
    _ builder: URL,
    for configuration: ProjectConfiguration.Flat,
    scratchDirectory: ScratchDirectoryStructure
  ) async throws(Error) {
    let context = _BuilderContextImpl(
      buildDirectory: scratchDirectory.build
    )

    let inputPipe = Pipe()
    let process = Process()

    process.executableURL = builder
    process.standardInput = inputPipe
    process.currentDirectoryURL = scratchDirectory.sources
      .actuallyResolvingSymlinksInPath()
    process.arguments = []

    let processWaitSemaphore = AsyncSemaphore(value: 0)

    process.terminationHandler = { _ in
      processWaitSemaphore.signal()
    }

    do {
      _ = try process.runAndLog()
      let data = try JSONEncoder().encode(context)
      inputPipe.fileHandleForWriting.write(data)
      inputPipe.fileHandleForWriting.write("\n")
      try? inputPipe.fileHandleForWriting.close()
      try await processWaitSemaphore.wait()

      let exitStatus = Int(process.terminationStatus)
      guard exitStatus == 0 else {
        throw Process.ErrorMessage.nonZeroExitStatus(process.commandString, exitStatus)
      }
    } catch {
      throw Error(.builderFailed, cause: error)
    }
  }
}
