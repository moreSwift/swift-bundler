import AsyncCollections
import Foundation
import SwiftBundlerBuilders
import Version
import ErrorKit

enum ProjectBuilder {
  static let builderProductName = "Builder"

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
        builtProducts: &builtProducts,
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

  /// Builds a project and returns the directory containing the built
  /// products on success.
  static func buildProject(
    _ name: String,
    configuration: ProjectConfiguration.Flat,
    packageDirectory: URL,
    scratchDirectory: ScratchDirectoryStructure,
    swiftToolchain: URL?
  ) async throws(Error) {
    // Just sitting here to raise alarms when more types are added
    switch configuration.builder.type {
      case .wholeProject:
        break
    }

    try await checkoutSource(
      configuration.source,
      at: scratchDirectory.sources,
      packageDirectory: packageDirectory
    )

    try await createBuilderPackage(
      for: configuration,
      packageDirectory: packageDirectory,
      scratchDirectory: scratchDirectory,
      swiftToolchain: swiftToolchain
    )
    let builder = try await buildBuilder(
      for: configuration,
      scratchDirectory: scratchDirectory,
      swiftToolchain: swiftToolchain
    )
    try await runBuilder(
      builder,
      for: configuration,
      scratchDirectory: scratchDirectory
    )
  }

  static func createBuilderPackage(
    for configuration: ProjectConfiguration.Flat,
    packageDirectory: URL,
    scratchDirectory: ScratchDirectoryStructure,
    swiftToolchain: URL?
  ) async throws(Error) {
    // Create builder source file symlink
    try Error.catch(withMessage: .failedToSymlinkBuilderSourceFile) {
      let masterBuilderSourceFile = packageDirectory / configuration.builder.name
      if FileManager.default.fileExists(atPath: scratchDirectory.builderSourceFile.path) {
        try FileManager.default.removeItem(at: scratchDirectory.builderSourceFile)
      }
      try FileManager.default.createSymbolicLink(
        at: scratchDirectory.builderSourceFile,
        withDestinationURL: masterBuilderSourceFile
      )
    }

    // Create/update the builder's Package.swift
    let toolsVersion = try await Error.catch {
      try await SwiftPackageManager.getToolsVersion(packageDirectory, toolchain: swiftToolchain)
    }

    let manifestContents = generateBuilderPackageManifest(
      toolsVersion,
      builderAPI: configuration.builder.api.normalized(
        usingDefault: SwiftBundler.gitURL
      ),
      rootPackageDirectory: packageDirectory,
      builderPackageDirectory: scratchDirectory.builder
    )

    try Error.catch(withMessage: .failedToWriteBuilderManifest) {
      try manifestContents.write(to: scratchDirectory.builderManifest)
    }
  }

  static func buildBuilder(
    for configuration: ProjectConfiguration.Flat,
    scratchDirectory: ScratchDirectoryStructure,
    swiftToolchain: URL?
  ) async throws(Error) -> URL {
    // Build the builder
    let buildContext = SwiftPackageManager.BuildContext(
      genericContext: GenericBuildContext(
        projectDirectory: scratchDirectory.builder,
        scratchDirectory: scratchDirectory.builder / ".build",
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
        product: builderProductName,
        buildContext: buildContext
      )

      productsDirectory = try await SwiftPackageManager.getProductsDirectory(buildContext)
    } catch {
      throw Error(.failedToBuildBuilder(name: configuration.builder.name), cause: error)
    }

    let builderFileName = HostPlatform.hostPlatform
      .executableFileName(forBaseName: builderProductName)
    let builder = productsDirectory / builderFileName
    return builder
  }

  static func runBuilder(
    _ builder: URL,
    for configuration: ProjectConfiguration.Flat,
    scratchDirectory: ScratchDirectoryStructure,
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

  static func generateBuilderPackageManifest(
    _ swiftVersion: Version,
    builderAPI: ProjectConfiguration.Source.Flat,
    rootPackageDirectory: URL,
    builderPackageDirectory: URL
  ) -> String {
    let dependency: String
    switch builderAPI {
      case .local(let path):
        let fullPath = rootPackageDirectory / path
        let relativePath = fullPath.path(relativeTo: builderPackageDirectory)
        dependency = """
                  .package(
                      name: "swift-bundler",
                      path: "\(relativePath)"
                  )
          """
      case .git(let url, let requirement):
        let revision: String
        switch requirement {
          case .revision(let value):
            revision = value
        }
        dependency = """
                  .package(
                      url: "\(url.absoluteString)",
                      revision: "\(revision)"
                  )
          """
    }

    return """
      // swift-tools-version:\(swiftVersion.major).\(swiftVersion.minor)
      import PackageDescription

      let package = Package(
          name: "Builder",
          platforms: [.macOS(.v10_15)],
          products: [
              .executable(name: "Builder", targets: ["Builder"])
          ],
          dependencies: [
      \(dependency)
          ],
          targets: [
              .executableTarget(
                  name: "\(builderProductName)",
                  dependencies: [
                      .product(name: "SwiftBundlerBuilders", package: "swift-bundler")
                  ]
              )
          ]
      )
      """
  }
}
