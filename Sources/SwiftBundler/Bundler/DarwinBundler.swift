import Foundation

/// The bundler for creating macOS apps.
enum DarwinBundler: Bundler {
  static let outputIsRunnable = true

  struct Context {
    /// Whether the build products were created by Xcode or not.
    var isXcodeBuild: Bool
    /// Whether the build products were built as universal binaries or not.
    var universal: Bool
    /// If `true`, the app bundle will not depend on any system-wide dependencies
    /// stalled (such as gtk).
    var standAlone: Bool
    /// The platform that the app should be bundled for.
    var platform: ApplePlatform
    /// The platform version that the executable was built for.
    var platformVersion: String
  }

  static func computeContext(
    context: BundlerContext,
    command: BundleCommand,
    manifest: PackageManifest
  ) throws(Error) -> Context {
    guard let applePlatform = context.platform.asApplePlatform else {
      throw Error(.unsupportedPlatform(context.platform))
    }

    guard let platformVersion = manifest.platformVersion(for: applePlatform) else {
      throw Error(.missingDarwinPlatformVersion(context.platform))
    }

    // Whether a universal application binary (arm64 and x86_64) will be created.
    let universal = command.arguments.universal || command.arguments.architectures.count > 1

    // Whether or not we are building with xcodebuild instead of swiftpm.
    let isUsingXcodebuild = Xcodebuild.isUsingXcodebuild(
      for: command,
      resolvedPlatform: context.platform
    )

    let additionalContext = Context(
      isXcodeBuild: command.builtWithXcode || isUsingXcodebuild,
      universal: universal,
      standAlone: command.arguments.standAlone,
      platform: applePlatform,
      platformVersion: platformVersion
    )
    return additionalContext
  }

  static func intendedOutput(
    in context: BundlerContext,
    _ additionalContext: Context
  ) -> BundlerOutputStructure {
    let bundle = context.outputDirectory
      .appendingPathComponent("\(context.appName).app")
    let structure = DarwinAppBundleStructure(
      at: bundle,
      platform: additionalContext.platform,
      appName: context.appName
    )
    return BundlerOutputStructure(
      bundle: bundle,
      executable: structure.mainExecutable
    )
  }

  static func bundle(
    _ context: BundlerContext,
    _ additionalContext: Context
  ) async throws(Error) -> BundlerOutputStructure {
    let outputStructure = intendedOutput(in: context, additionalContext)
    let appBundle = outputStructure.bundle

    log.info("Bundling '\(appBundle.lastPathComponent)'")

    let bundleStructure = DarwinAppBundleStructure(
      at: appBundle,
      platform: additionalContext.platform,
      appName: context.appName
    )

    // Create bundle skeleton
    try bundleStructure.createDirectories()

    try copyExecutable(
      at: context.executableArtifact,
      to: bundleStructure.mainExecutable
    )

    // Copy app icon and package resources
    let partialInfoPlist = try await copyResources(
      bundleStructure: bundleStructure,
      context: context,
      additionalContext: additionalContext
    )

    // Create PkgInfo and Info.plist
    try createMetadataFiles(
      bundleStructure: bundleStructure,
      context: context,
      additionalContext: additionalContext,
      partialInfoPlist: partialInfoPlist
    )

    // Copy helper executables, dynamic libraries and frameworks
    try await copyDependencies(
      bundleStructure: bundleStructure,
      context: context,
      additionalContext: additionalContext
    )

    // Embed provisioning profile if necessary
    if let provisioningProfile = try await Self.provisioningProfile(for: context) {
      try Self.embedProvisioningProfile(provisioningProfile, in: appBundle)
    }

    try await Self.sign(
      appBundle: appBundle,
      context: context,
      additionalContext: additionalContext
    )

    return outputStructure
  }

  // MARK: Private methods

  /// Creates the app's `PkgInfo` and `Info.plist` files.
  private static func createMetadataFiles(
    bundleStructure: DarwinAppBundleStructure,
    context: BundlerContext,
    additionalContext: Context,
    partialInfoPlist: [String: Any]?
  ) throws(Error) {
    try Self.createPkgInfoFile(at: bundleStructure.pkgInfoFile)

    try Self.createInfoPlistFile(
      at: bundleStructure.infoPlistFile,
      appName: context.appName,
      appConfiguration: context.appConfiguration,
      platform: additionalContext.platform,
      platformVersion: additionalContext.platformVersion,
      partialInfoPlist: partialInfoPlist
    )
  }

  /// Copies app icon and package resources into the app bundle.
  private static func copyResources(
    bundleStructure: DarwinAppBundleStructure,
    context: BundlerContext,
    additionalContext: Context
  ) async throws(Error) -> [String: Any]? {
    var partialInfoPlist: [String: Any]? = nil
    if let path = context.appConfiguration.icon {
      let icon = context.packageDirectory / path
      partialInfoPlist = try await Self.compileAppIcon(
        at: icon,
        to: bundleStructure.appIconFile,
        for: context.platform,
        withPlatformVersion: additionalContext.platformVersion
      )
    }

    do {
      let appIconURL: URL?
      if let iconFile = context.appConfiguration.icon {
        appIconURL = context.packageDirectory / iconFile
      } else {
        appIconURL = nil
      }
      try await ResourceBundler.copyResources(
        from: context.productsDirectory,
        to: bundleStructure.resourcesDirectory,
        fixBundles: !additionalContext.isXcodeBuild && !additionalContext.universal,
        platform: context.platform,
        platformVersion: additionalContext.platformVersion,
        packageName: context.packageName,
        productName: context.appConfiguration.product,
        iconURL: appIconURL
      )
    } catch {
      throw Error(.failedToCopyResourceBundles, cause: error)
    }

    return partialInfoPlist
  }

  /// Copies the app's helper executables, dynamic libraries and frameworks
  /// into the app bundle.
  private static func copyDependencies(
    bundleStructure: DarwinAppBundleStructure,
    context: BundlerContext,
    additionalContext: Context
  ) async throws(Error) {
    // Copy all executable dependencies into the bundle next to the main executable
    let executableDirectory = bundleStructure.mainExecutable.deletingLastPathComponent()
    for (name, dependency) in context.builtDependencies {
      guard dependency.product.type == .executable else {
        continue
      }

      for artifact in dependency.artifacts {
        do {
          let source = artifact.location
          try FileManager.default.copyItem(
            at: source,
            to: executableDirectory / source.lastPathComponent
          )
        } catch {
          throw Error(.failedToCopyExecutableDependency(name: name), cause: error)
        }
      }
    }

    // Copy dynamic libraries and frameworks into the bundle
    do {
      try await DynamicLibraryBundler.copyDynamicDependencies(
        dependedOnBy: bundleStructure.mainExecutable,
        toLibraryDirectory: bundleStructure.librariesDirectory,
        orFrameworkDirectory: bundleStructure.frameworksDirectory,
        productsDirectory: context.productsDirectory,
        isXcodeBuild: additionalContext.isXcodeBuild,
        universal: additionalContext.universal,
        makeStandAlone: additionalContext.standAlone
      )
    } catch {
      throw Error(.failedToCopyDynamicLibraries, cause: error)
    }
  }

  /// Signs the given app bundle if requested. If not required by the target
  /// platform but not requested, then we sign with an adhoc signature.
  private static func sign(
    appBundle: URL,
    context: BundlerContext,
    additionalContext: Context
  ) async throws(Error) {
    try await Error.catch {
      if let codeSigningContext = context.darwinCodeSigningContext {
        try await CodeSigner.signAppBundle(
          bundle: appBundle,
          identityId: codeSigningContext.identity.id,
          bundleIdentifier: context.appConfiguration.identifier,
          platform: additionalContext.platform,
          entitlements: codeSigningContext.entitlements
        )
      } else {
        // Codesign using an adhoc signature
        try await CodeSigner.signAppBundle(
          bundle: appBundle,
          identityId: "-",
          bundleIdentifier: context.appConfiguration.identifier,
          platform: additionalContext.platform,
          entitlements: nil
        )
      }
    }
  }

  /// Locates the provisioning profile to use for the given bundler context.
  /// Returns `nil` if the context doesn't require a profile, and throws an
  /// error if a provisioning profile is required but couldn't be located.
  private static func provisioningProfile(
    for context: BundlerContext
  ) async throws(Error) -> URL? {
    // If the user provided a provisioning profile, use it
    if let profile = context.darwinCodeSigningContext?.manualProvisioningProfile {
      return profile
    }

    // Simulators and hosts don't require provisioning profiles
    guard
      case .connected(let device) = context.device,
      !device.platform.isSimulator
    else {
      return nil
    }

    // If the target platform requires provisioning profiles, locate or
    // generate one. This requires a code signing context.
    guard let codeSigningContext = context.darwinCodeSigningContext else {
      throw Error(.missingCodeSigningContextForProvisioning(device.platform.os))
    }

    do {
      return
        try await ProvisioningProfileManager
        .locateOrGenerateSuitableProvisioningProfile(
          bundleIdentifier: context.appConfiguration.identifier,
          deviceId: device.id,
          deviceOS: device.platform.os,
          identity: codeSigningContext.identity
        )
    } catch {
      throw Error(.failedToGenerateProvisioningProfile, cause: error)
    }
  }

  /// Copies the built executable into the app bundle.
  /// - Parameters:
  ///   - source: The location of the built executable.
  ///   - destination: The target location of the built executable (the file not the directory).
  private static func copyExecutable(
    at source: URL,
    to destination: URL
  ) throws(Error) {
    log.info("Copying executable")
    do {
      try FileManager.default.copyItem(at: source, to: destination)
    } catch {
      throw Error(
        .failedToCopyExecutable(source: source, destination: destination),
        cause: error
      )
    }
  }

  /// Create's a `PkgInfo` file.
  private static func createPkgInfoFile(at pkgInfoFile: URL) throws(Error) {
    log.info("Creating 'PkgInfo'")
    let pkgInfoBytes: [UInt8] = [0x41, 0x50, 0x50, 0x4c, 0x3f, 0x3f, 0x3f, 0x3f]
    let pkgInfoData = Data(bytes: pkgInfoBytes, count: pkgInfoBytes.count)

    try Error.catch(withMessage: .failedToCreatePkgInfo(file: pkgInfoFile)) {
      try pkgInfoData.write(to: pkgInfoFile)
    }
  }

  /// Creates an app's `Info.plist` file.
  private static func createInfoPlistFile(
    at infoPlistFile: URL,
    appName: String,
    appConfiguration: AppConfiguration.Flat,
    platform: ApplePlatform,
    platformVersion: String,
    partialInfoPlist: [String: Any]?
  ) throws(Error) {
    log.info("Creating 'Info.plist'")
    try Error.catch(withMessage: .failedToCreateInfoPlist) {
      try PlistCreator.createAppInfoPlist(
        at: infoPlistFile,
        appName: appName,
        configuration: appConfiguration,
        platform: platform.platform,
        platformVersion: platformVersion,
        partialInfoPlist: partialInfoPlist
      )
    }
  }

  /// If given an `icns`, the `icns` gets copied to the output file. If given
  /// a `png`, an `icns` is created from the `png`.
  ///
  /// The files are not validated any further than checking their file extensions.
  /// - Parameters:
  ///   - inputIconFile: The app's icon. Should be either an `icns` file or a
  ///     1024x1024 `png` with an alpha channel.
  ///   - outputIconFile: The `icns` file to output to.
  ///   - platform: The platform the icon is being created for.
  ///   - platformVersion: The platform version the icon is being created for.
  /// - Throws: If the png exists and there is an error while converting it to
  ///   `icns`, or if the file is neither an `icns` or a `png`.
  private static func compileAppIcon(
    at inputIconFile: URL,
    to outputIconFile: URL,
    for platform: Platform,
    withPlatformVersion platformVersion: String
  ) async throws(Error) -> [String: Any]? {
    // Copy `AppIcon.icns` if present

    var partialInfoPlist: [String: Any]? = nil

    if inputIconFile.pathExtension == "icns" {
      log.info("Copying '\(inputIconFile.lastPathComponent)'")
      do {
        try FileManager.default.copyItem(at: inputIconFile, to: outputIconFile)
      } catch {
        throw Error(
          .failedToCopyICNS(source: inputIconFile, destination: outputIconFile),
          cause: error
        )
      }
    } else if inputIconFile.pathExtension == "icon" {
      log.info(
        "Creating '\(outputIconFile.lastPathComponent)' from '\(inputIconFile.lastPathComponent)'")

      partialInfoPlist = try await Error.catch(withMessage: .failedToCreateIcon) {
        return try await LayeredIconCompiler.createIcon(
          from: inputIconFile,
          outputFile: outputIconFile,
          forPlatform: platform,
          withPlatformVersion: platformVersion
        )
      }

    } else if inputIconFile.pathExtension == "png" {
      log.info(
        "Creating '\(outputIconFile.lastPathComponent)' from '\(inputIconFile.lastPathComponent)'"
      )

      try await Error.catch(withMessage: .failedToCreateIcon) {
        try await IconSetCreator.createIcns(
          from: inputIconFile,
          outputFile: outputIconFile
        )
      }
    } else {
      throw Error(.invalidAppIconFile(inputIconFile))
    }

    return partialInfoPlist
  }

  private static func embedProvisioningProfile(
    _ provisioningProfile: URL,
    in bundle: URL
  ) throws(Error) {
    log.info("Embedding provisioning profile")

    try Error.catch(withMessage: .failedToCopyProvisioningProfile) {
      try FileManager.default.copyItem(
        at: provisioningProfile,
        to: bundle.appendingPathComponent("embedded.mobileprovision")
      )
    }
  }
}
