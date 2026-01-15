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

  static func buildDependencies(
    _ dependencies: [AppConfiguration.Dependency],
    packageConfiguration: PackageConfiguration.Flat,
    context: GenericBuildContext,
    swiftToolchain: URL?,
    appName: String,
    dryRun: Bool
  ) async throws(Error) -> [String: BuiltProduct] {
    var builtProjects: Set<String> = []
    var builtProducts: [String: BuiltProduct] = [:]
    for dependency in dependencies {
      try await buildDependency(
        dependency,
        packageConfiguration: packageConfiguration,
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

  private static func buildDependency(
    _ dependency: AppConfiguration.Dependency,
    packageConfiguration: PackageConfiguration.Flat,
    context: GenericBuildContext,
    swiftToolchain: URL?,
    appName: String,
    dryRun: Bool,
    builtProjects: inout Set<String>,
    builtProducts: inout [String: BuiltProduct]
  ) async throws(Error) {
    let projectName = dependency.project

    // Special case the root project (just use SwiftPM)
    if projectName == ProjectConfiguration.rootProjectName {
      if !dryRun {
        log.info("Building product '\(dependency.product)'")
      }

      let (productName, builtProduct) = try await buildRootProjectProduct(
        dependency.product,
        context: context,
        swiftToolchain: swiftToolchain,
        dryRun: dryRun
      )
      builtProducts[productName] = builtProduct
      return
    }

    guard let project = packageConfiguration.projects[projectName] else {
      throw Error(.missingProject(name: projectName, appName: appName))
    }

    guard let product = project.products[dependency.product] else {
      let message = ErrorMessage.missingProduct(
        project: projectName,
        product: dependency.product,
        appName: appName
      )
      throw Error(message)
    }

    let projectScratchDirectory = ScratchDirectoryStructure(
      scratchDirectory: context.scratchDirectory / projectName
    )

    let productsDirectoryExists =
      projectScratchDirectory.products.exists(withType: .directory)

    let requiresBuilding = !builtProjects.contains(dependency.project)
    builtProjects.insert(dependency.project)

    let productPath = product.artifactPath(
      whenNamed: dependency.product,
      platform: context.platform
    )
    let auxiliaryArtifactPaths = product.auxiliaryArtifactPaths(
      whenNamed: dependency.product,
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
      log.info("Copying product '\(dependency.identifier)'")
    }

    let artifactPaths = [productPath] + auxiliaryArtifactPaths
    let artifacts = try artifactPaths.compactMap { (path) throws(Error) -> Artifact? in
      let builtProduct = projectScratchDirectory.build / path
      return try copyArtifact(
        builtProduct,
        to: projectScratchDirectory.products,
        isRequired: path == productPath,
        product: dependency.product,
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

  static func buildRootProjectProduct(
    _ product: String,
    context: GenericBuildContext,
    swiftToolchain: URL?,
    dryRun: Bool
  ) async throws(Error) -> (String, BuiltProduct) {
    let manifest: PackageManifest
    do {
      manifest = try await SwiftPackageManager.loadPackageManifest(
        from: context.projectDirectory,
        toolchain: swiftToolchain
      )
    } catch {
      throw Error(.failedToBuildRootProjectProduct(name: product), cause: error)
    }

    // Locate product in manifest
    guard
      let manifestProduct = manifest.products.first(where: { $0.name == product })
    else {
      let project = ProjectConfiguration.rootProjectName
      throw Error(.noSuchProduct(project: project, product: product))
    }

    // We only support 'helper executable'-style dependencies for SwiftPM products at the moment
    guard manifestProduct.type == .executable else {
      let message = ErrorMessage.unsupportedRootProjectProductType(
        manifestProduct.type,
        product: product
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
          product: product,
          buildContext: buildContext
        )
      }

      productsDirectory = try await SwiftPackageManager.getProductsDirectory(
        buildContext
      )
    } catch {
      throw Error(.failedToBuildRootProjectProduct(name: product), cause: error)
    }

    // Produce built product description
    let productConfiguration = ProjectConfiguration.Product.Flat(
      type: .executable,
      outputDirectory: nil
    )
    let artifactPath = productConfiguration.artifactPath(
      whenNamed: product,
      platform: context.platform
    )
    let artifacts = [
      ProjectBuilder.Artifact(location: productsDirectory / artifactPath)
    ]
    let builtProduct = BuiltProduct(product: productConfiguration, artifacts: artifacts)

    return (product, builtProduct)
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
