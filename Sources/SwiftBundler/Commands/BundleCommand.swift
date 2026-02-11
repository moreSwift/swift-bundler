import ArgumentParser
import Foundation
import X509

/// The subcommand for creating app bundles for a package.
struct BundleCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "bundle",
    abstract: "Create an app bundle from a package."
  )

  /// Arguments in common with the run command.
  @OptionGroup
  var arguments: BundleArguments

  /// Whether to skip the build step or not.
  @Flag(
    name: .long,
    help: "Skip the build step."
  )
  var skipBuild = false

  #if os(macOS)
    /// If `true`, treat the products in the products directory as if they were built by Xcode (which is the same as universal builds by SwiftPM).
    ///
    /// Can only be `true` when ``skipBuild`` is `true`.
    @Flag(
      name: .long,
      help: .init(
        stringLiteral:
          """
          Treats the products in the products directory as if they were built \
          by Xcode (which is the same as universal builds by SwiftPM). Can \
          only be set when `--skip-build` is supplied.
          """
      ))
  #endif
  var builtWithXcode = false

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages.")
  public var verbose = false

  var hotReloadingEnabled = false

  // TODO: fix this weird pattern with a better config loading system
  /// Used to avoid loading configuration twice when RunCommand is used.
  static var bundlerConfiguration:
    (
      appName: String,
      appConfiguration: AppConfiguration.Flat,
      configuration: PackageConfiguration.Flat
    )?

  init() {
    _arguments = OptionGroup()
  }

  init(
    arguments: OptionGroup<BundleArguments>,
    skipBuild: Bool,
    builtWithXcode: Bool,
    hotReloadingEnabled: Bool
  ) {
    _arguments = arguments
    self.skipBuild = skipBuild
    self.builtWithXcode = builtWithXcode
    self.hotReloadingEnabled = hotReloadingEnabled
  }

  static func validateArguments(
    _ arguments: BundleArguments,
    platform: Platform,
    skipBuild: Bool,
    builtWithXcode: Bool
  ) -> Bool {
    // Validate parameters
    #if os(macOS)
      if !skipBuild {
        guard arguments.productsDirectory == nil, !builtWithXcode else {
          log.error(
            """
            '--products-directory' and '--built-with-xcode' are only compatible \
            with '--skip-build'
            """
          )
          return false
        }
      }
    #endif

    for architecture in arguments.architectures {
      guard platform.supportedArchitectures.contains(architecture) else {
        log.error(
          """
          Architecture '\(architecture.rawValue)' is not supported when targeting \
          '\(platform.displayName)'
          """
        )
        return false
      }
    }

    if HostPlatform.hostPlatform != .macOS && platform != HostPlatform.hostPlatform.platform {
      let hostPlatform = HostPlatform.hostPlatform.platform.displayName
      log.error("'--platform \(platform)' is not supported on \(hostPlatform)")
      return false
    }

    if HostPlatform.hostPlatform == .windows && arguments.strip {
      log.error("'--strip' is not supported on Windows")
      return false
    }

    guard arguments.bundler.isSupportedOnHostPlatform else {
      log.error(
        """
        The '\(arguments.bundler.rawValue)' bundler is not supported on the \
        current host platform. Supported bundlers: \
        \(BundlerChoice.supportedHostValuesDescription)
        """
      )
      return false
    }

    guard arguments.bundler.supportedTargetPlatforms.contains(platform) else {
      let alternatives = BundlerChoice.allCases.filter { choice in
        choice.supportedTargetPlatforms.contains(platform)
      }
      let alternativesDescription = "(\(alternatives.map(\.rawValue).joined(separator: "|")))"
      log.error(
        """
        The '\(arguments.bundler.rawValue)' bundler doesn't support bundling \
        for '\(platform)'. Supported target platforms: \
        \(BundlerChoice.supportedHostValuesDescription). Valid alternative \
        bundlers: \(alternativesDescription)
        """
      )
      return false
    }

    if [.macOS, .macCatalyst].contains(platform)
      && arguments.architectures.count == 1
      && arguments.architectures[0] != .host
    {
      if arguments.xcodebuild {
        // It throws the following error
        // could not find module 'MacroToolkit' for target 'arm64-apple-macos';
        // found: x86_64-apple-macos, at: <scratch>/Build/Products/Debug/
        // MacroToolkit.swiftmodule
        log.warning(
          """
          Cross compilation for macOS with '--xcodebuild' often fails due to a \
          bug in xcodebuild's macro handling. Perform a '--universal' build instead \
          or omit '--xcodebuild'.
          """
        )
      } else {
        log.warning(
          """
          Metadata insertion is broken when cross-compiling for macOS. Build with \
          '--universal --xcodebuild' instead to work around this issue if you \
          rely on metadata.
          """
        )
      }
    }

    // macOS-only arguments
    #if os(macOS)
      if (arguments.universal || arguments.architectures.count > 1)
        && (!arguments.xcodebuild || arguments.noXcodebuild)
      {
        log.warning(
          """
          SwiftPM has multiple bugs related to universal builds. If this build fails, \
          try building with '--xcodebuild' as a workaround.
          """
        )
      }

      if case .other(.physical) = platform.asApplePlatform?.partitioned, arguments.universal {
        log.error(
          """
          '--universal' is not compatible with '--platform \
          \(platform.rawValue)'
          """
        )
        return false
      }

      if platform != .macOS && arguments.standAlone {
        log.error("'--experimental-stand-alone' only works when targeting macOS (and that excludes Mac Catalyst)")
        return false
      }

      switch platform {
        case .iOS, .visionOS, .tvOS:
          break
        default:
          if arguments.provisioningProfile != nil {
            log.error(
              """
              '--provisioning-profile' is only available when building \
              apps for physical iOS, visionOS and tvOS devices
              """
            )
            return false
          }
      }
    #else
      if builtWithXcode {
        log.error(
          """
          '--built-with-xcode' is only available on macOS
          """
        )
      }
    #endif

    return true
  }

  static func resolveCodesigningContext(
    codesignArgument: Bool?,
    identityArgument: String?,
    provisioningProfile: URL?,
    entitlements: URL?,
    platform: Platform
  ) async throws(RichError<SwiftBundlerError>) -> BundlerContext.DarwinCodeSigningContext? {
    guard let platform = platform.asApplePlatform else {
      let invalidArguments = [
        ("--codesign", codesignArgument == true),
        ("--identity", identityArgument != nil),
        ("--entitlements", entitlements != nil),
        ("--provisioning-profile", provisioningProfile != nil),
      ].filter { $0.1 }.map { $0.0 }

      guard invalidArguments.count == 0 else {
        let list = invalidArguments.map { "'\($0)'" }
          .joinedGrammatically(
            withTrailingVerb: Verb(
              singular: "isn't",
              plural: "aren't"
            )
          )
        let reason = "\(list) supported when targeting '\(platform.name)'"
        throw RichError(SwiftBundlerError.failedToResolveCodesigningConfiguration(reason: reason))
      }

      return nil
    }

    let codesign: Bool
    if platform.requiresProvisioningProfiles {
      if codesignArgument == nil || codesignArgument == true {
        codesign = true
      } else {
        let reason = """
          \(platform.platform.name) is incompatible with '--no-codesign' \
          because it requires provisioning profiles
          """
        throw RichError(SwiftBundlerError.failedToResolveCodesigningConfiguration(reason: reason))
      }
    } else {
      codesign = codesignArgument ?? false
    }

    guard codesign else {
      let invalidArguments = [
        ("--identity", identityArgument != nil),
        ("--entitlements", entitlements != nil),
        ("--provisioning-profile", provisioningProfile != nil),
      ].filter { $0.1 }.map { $0.0 }
      guard invalidArguments.count == 0 else {
        let list = invalidArguments.map { "'\($0)'" }
          .joinedGrammatically(withTrailingVerb: .be)
        let reason = "\(list) invalid when not codesigning"
        throw RichError(SwiftBundlerError.failedToResolveCodesigningConfiguration(reason: reason))
      }
      return nil
    }

    do {
      let identity: CodeSigner.Identity
      if let identityShortName = identityArgument {
        identity = try await RichError<SwiftBundlerError>.catch {
          try await CodeSigner.resolveIdentity(shortName: identityShortName)
        }
      } else {
        let identities = try await RichError<SwiftBundlerError>.catch {
          try await CodeSigner.enumerateIdentities()
        }

        guard let firstIdentity = identities.first else {
          let reason = """
            No codesigning identities found. Please sign into Xcode and try again.
            """
          throw RichError(SwiftBundlerError.failedToResolveCodesigningConfiguration(reason: reason))
        }

        if identities.count > 1 {
          log.info("Multiple codesigning identities found, using \(firstIdentity)")
        }

        identity = firstIdentity
      }

      return BundlerContext.DarwinCodeSigningContext(
        identity: identity,
        entitlements: entitlements,
        manualProvisioningProfile: provisioningProfile
      )
    } catch {
      // Add clarification in case codesigning inference causes any confusion
      if codesignArgument == nil {
        log.info(
          """
          \(platform.platform.name) requires codesigning, so '--codesign' has \
          been inferred.
          """
        )
      }
      // TODO: Remove this once full typed throws has been enabled
      // swiftlint:disable:next force_cast
      throw error as! RichError<SwiftBundlerError>
    }
  }

  /// Resolves the target platform, returning the resolved target device as
  /// well if the user specified a target device.
  static func resolvePlatform(
    platform: Platform?,
    deviceSpecifier: String?,
    simulatorSpecifier: String?
  ) async throws(RichError<SwiftBundlerError>) -> (Platform, Device?) {
    if let platform = platform, deviceSpecifier == nil, simulatorSpecifier == nil {
      return (platform, nil)
    }

    let device = try await resolveDevice(
      platform: platform,
      deviceSpecifier: deviceSpecifier,
      simulatorSpecifier: simulatorSpecifier
    )
    return (device.platform, device)
  }

  static func resolveDevice(
    platform: Platform?,
    deviceSpecifier: String?,
    simulatorSpecifier: String?
  ) async throws(RichError<SwiftBundlerError>) -> Device {
    // '--device' and '--simulator' are mutually exclusive
    guard deviceSpecifier == nil || simulatorSpecifier == nil else {
      let reason = "'--device' and '--simulator' cannot be used at the same time"
      throw RichError(.failedToResolveTargetDevice(reason: reason))
    }

    if let deviceSpecifier {
      // This will also find simulators (--device can be used to specify any
      // destination).
      return try await RichError<SwiftBundlerError>.catch {
        try await DeviceManager.resolve(
          specifier: deviceSpecifier,
          platform: platform
        )
      }
    } else if let simulatorSpecifier {
      if let platform = platform, !platform.isSimulator {
        let reason = "'--simulator' is incompatible with '--platform \(platform)'"
        throw RichError(SwiftBundlerError.failedToResolveTargetDevice(reason: reason))
      }

      let matchedSimulators = try await RichError<SwiftBundlerError>.catch {
        try await SimulatorManager.listAvailableSimulators(
          searchTerm: simulatorSpecifier
        )
      }.sorted { first, second in
        // Put booted simulators first for convenience and put shorter names
        // first (otherwise there'd be no guarantee the "iPhone 15" matches
        // "iPhone 15" when both "iPhone 15" and "iPhone 15 Pro" exist, and
        // you'd be left with no way to disambiguate).
        if !first.isBooted && second.isBooted {
          return false
        } else if first.name.count > second.name.count {
          return false
        } else {
          return true
        }
      }.filter { simulator in
        // Filter out simulators with the wrong platform
        if let platform = platform {
          return simulator.os.simulatorPlatform.platform == platform
        } else {
          return true
        }
      }

      guard let simulator = matchedSimulators.first else {
        let platformCondition = platform.map { " with platform '\($0)'" } ?? ""
        let reason = """
          No simulator found matching '\(simulatorSpecifier)'\(platformCondition). Use \
          'swift bundler simulators list' to list available simulators.
          """
        throw RichError(SwiftBundlerError.failedToResolveTargetDevice(reason: reason))
      }

      if matchedSimulators.count > 1 {
        log.warning(
          "Multiple simulators matched '\(simulatorSpecifier)', using '\(simulator.name)'"
        )
      }

      return simulator.device
    } else {
      let hostPlatform = HostPlatform.hostPlatform
      switch platform {
        case .none, hostPlatform.platform:
          // FIXME: Resolve architecture correctly here when cross compiling
          return Device.host(hostPlatform, .host)
        case .macCatalyst:
          // FIXME: Resolve architecture correctly here when cross compiling
          return Device.macCatalyst(.host)
        case .some(let platform) where platform.isSimulator:
          let matchedSimulators = try await RichError<SwiftBundlerError>.catch {
            try await SimulatorManager.listAvailableSimulators()
          }.filter { simulator in
            simulator.isBooted
              && simulator.isAvailable
              && simulator.os.simulatorPlatform.platform == platform
          }.sorted { first, second in
            first.name < second.name
          }

          guard let simulator = matchedSimulators.first else {
            let reason =
              Output {
                """
                No booted simulators found for platform '\(platform)'. Boot \
                \(platform.os.rawValue.withIndefiniteArticle) simulator, or \
                specify a simulator to use via '--simulator <id-or-search-term>'

                """

                Section("List available simulators") {
                  ExampleCommand("swift bundler simulators list")
                }

                Section("Boot a simulator", trailingNewline: false) {
                  ExampleCommand("swift bundler simulators boot <id-or-name>")
                }
              }.description
            throw RichError(SwiftBundlerError.failedToResolveTargetDevice(reason: reason))
          }

          if matchedSimulators.count > 1 {
            log.warning(
              "Found multiple booted \(platform.os.rawValue) simulators, using '\(simulator.name)'"
            )
          }

          return simulator.device
        case .some(let platform):
          let reason =
            Output {
              """
              '--platform \(platform.name)' requires '--device <id-or-search-term>'

              """

              Section("List available devices", trailingNewline: false) {
                ExampleCommand("swift bundler devices list")
              }
            }.description
          throw RichError(SwiftBundlerError.failedToResolveTargetDevice(reason: reason))
      }
    }
  }

  func getArchitectures(platform: Platform) -> [BuildArchitecture] {
    let architectures: [BuildArchitecture]
    if arguments.universal {
      architectures = platform.supportedArchitectures
    } else if !arguments.architectures.isEmpty {
      architectures = arguments.architectures
    } else {
      architectures = [platform.defaultTargetArchitecture(hostArchitecture: .host)]
    }
    return architectures
  }

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    let (platform, device) = try await Self.resolvePlatform(
      platform: arguments.platform,
      deviceSpecifier: arguments.deviceSpecifier,
      simulatorSpecifier: arguments.simulatorSpecifier
    )
    _ = try await doBundling(resolvedPlatform: platform, resolvedDevice: device)
  }

  // swiftlint:disable cyclomatic_complexity
  /// - Parameters
  ///   - dryRun: During a dry run, all of the validation steps are
  ///     performed without performing any side effects. This allows the
  ///     `RunCommand` to figure out where the output bundle will end up even
  ///     when the user instructs it to skip bundling.
  ///   - resolvedPlatform: The target platform resolved from the various
  ///     arguments users can use to specify it. This parameter purely exists
  ///     to allow ``RunCommand`` to avoid resolving the target platform twice
  ///     (once for its own use and once when this method gets called).
  ///   - resolvedDevice: Must be provided when provisioning profiles are
  ///     expected to be generated.
  /// - Returns: A description of the structure of the bundler's output.
  func doBundling(
    dryRun: Bool = false,
    resolvedPlatform: Platform,
    resolvedDevice: Device? = nil
  ) async throws(RichError<SwiftBundlerError>) -> BundlerOutputStructure {
    let resolvedCodesigningContext = try await Self.resolveCodesigningContext(
      codesignArgument: arguments.codesign,
      identityArgument: arguments.identity,
      provisioningProfile: arguments.provisioningProfile,
      entitlements: arguments.entitlements,
      platform: resolvedPlatform
    )

    // Time execution so that we can report it to the user.
    let (elapsed, bundlerOutputStructure) = try await Stopwatch.time { () async throws(RichError<SwiftBundlerError>) in
      // Load configuration
      let packageDirectory = arguments.packageDirectory ?? URL.currentDirectory
      let scratchDirectory =
        arguments.scratchDirectory ?? (packageDirectory / ".build")

      let (appName, appConfiguration, configuration) = try await Self.getConfiguration(
        arguments.appName,
        packageDirectory: packageDirectory,
        context: ConfigurationFlattener.Context(
          platform: resolvedPlatform,
          bundler: arguments.bundler
        ),
        customFile: arguments.configurationFileOverride
      )

      guard
        Self.validateArguments(
          arguments,
          platform: resolvedPlatform,
          skipBuild: skipBuild,
          builtWithXcode: builtWithXcode
        )
      else {
        Foundation.exit(1)
      }

      // Get relevant configuration
      let architectures = getArchitectures(platform: resolvedPlatform)

      // Whether or not we are building with xcodebuild instead of swiftpm.
      let isUsingXcodebuild = Xcodebuild.isUsingXcodebuild(
        for: self,
        resolvedPlatform: resolvedPlatform
      )

      if isUsingXcodebuild {
        // Terminate the program if the project is an Xcodeproj based project.
        let xcodeprojs = try RichError<SwiftBundlerError>.catch {
          try FileManager.default.contentsOfDirectory(
            at: packageDirectory,
            includingPropertiesForKeys: nil
          ).filter({
            $0.pathExtension.contains("xcodeproj") || $0.pathExtension.contains("xcworkspace")
          })
        }

        guard xcodeprojs.isEmpty else {
          for xcodeproj in xcodeprojs {
            if xcodeproj.path.contains("xcodeproj") {
              log.error("An xcodeproj was located at the following path: \(xcodeproj.path)")
            } else if xcodeproj.path.contains("xcworkspace") {
              log.error("An xcworkspace was located at the following path: \(xcodeproj.path)")
            }
          }
          throw RichError(.invalidXcodeprojDetected)
        }
      }

      let outputDirectory = Self.outputDirectory(for: scratchDirectory)

      // Load package manifest
      log.info("Loading package manifest")
      let manifest = try await RichError<SwiftBundlerError>.catch {
        try await SwiftPackageManager.loadPackageManifest(from: packageDirectory)
      }

      let platformVersion =
        resolvedPlatform.asApplePlatform.map { platform in
          manifest.platformVersion(for: platform)
        } ?? nil

      let metadataDirectory = outputDirectory / "metadata"
      if !metadataDirectory.exists() {
        try RichError<SwiftBundlerError>.catch {
          try FileManager.default.createDirectory(
            at: metadataDirectory,
            withIntermediateDirectories: true
          )
        }
      }
      let compiledMetadata = try await RichError<SwiftBundlerError>.catch {
        return try await MetadataInserter.compileMetadata(
          in: metadataDirectory,
          for: MetadataInserter.metadata(for: appConfiguration),
          architectures: architectures,
          platform: resolvedPlatform
        )
      }

      let buildContext = SwiftPackageManager.BuildContext(
        genericContext: GenericBuildContext(
          projectDirectory: packageDirectory,
          scratchDirectory: scratchDirectory,
          configuration: arguments.buildConfiguration,
          architectures: architectures,
          platform: resolvedPlatform,
          platformVersion: platformVersion,
          additionalArguments: isUsingXcodebuild
            ? arguments.additionalXcodeBuildArguments
            : arguments.additionalSwiftPMArguments
        ),
        hotReloadingEnabled: hotReloadingEnabled,
        isGUIExecutable: true,
        compiledMetadata: compiledMetadata
      )

      // Get build output directory
      let productsDirectory: URL

      if !isUsingXcodebuild {
        if let argumentsProductsDirectory = arguments.productsDirectory {
          productsDirectory = argumentsProductsDirectory
        } else {
          productsDirectory = try await RichError<SwiftBundlerError>.catch {
            try await SwiftPackageManager.getProductsDirectory(buildContext)
          }
        }
      } else {
        let archString = architectures.compactMap({ $0.rawValue }).joined(separator: "_")
        // xcodebuild adds a platform suffix to the products directory for
        // certain platforms. E.g. it's 'Release-xrsimulator' for visionOS.
        let productsDirectoryBase = arguments.buildConfiguration.rawValue.capitalized
        let swiftpmSuffix: String
        let xcodeSuffix: String
        if let suffix = resolvedPlatform.xcodeProductDirectorySuffix {
          xcodeSuffix = "-\(suffix)"
          swiftpmSuffix = suffix
        } else {
          xcodeSuffix = ""
          swiftpmSuffix = resolvedPlatform.rawValue
        }
        productsDirectory =
          arguments.productsDirectory
          ?? (packageDirectory
            / ".build/\(archString)-apple-\(swiftpmSuffix)"
            / "Build/Products/\(productsDirectoryBase)\(xcodeSuffix)")
      }

      var originalExecutableArtifact = productsDirectory / appConfiguration.product
      if let fileExtension = resolvedPlatform.executableFileExtension {
        originalExecutableArtifact = originalExecutableArtifact
          .appendingPathExtension(fileExtension)
      }
      let executableArtifact: URL
      if arguments.strip {
        executableArtifact = originalExecutableArtifact.appendingPathExtension("stripped")
      } else {
        executableArtifact = originalExecutableArtifact
      }

      var bundlerContext = BundlerContext(
        appName: appName,
        packageName: manifest.name,
        appConfiguration: appConfiguration,
        packageDirectory: packageDirectory,
        productsDirectory: productsDirectory,
        outputDirectory: outputDirectory,
        platform: resolvedPlatform,
        device: resolvedDevice,
        darwinCodeSigningContext: resolvedCodesigningContext,
        builtDependencies: [:],
        executableArtifact: executableArtifact
      )

      // If this is a dry run, drop out just before we start actually do stuff.
      guard !dryRun else {
        return try Self.intendedOutput(
          of: arguments.bundler.bundler,
          context: bundlerContext,
          command: self,
          manifest: manifest
        )
      }

      let dependenciesScratchDirectory = outputDirectory / "projects"

      var dependencyContext = buildContext.genericContext
      dependencyContext.scratchDirectory = dependenciesScratchDirectory
      let dependencies = try await RichError<SwiftBundlerError>.catch {
        try await ProjectBuilder.buildDependencies(
          appConfiguration.dependencies,
          packageConfiguration: configuration,
          context: dependencyContext,
          appName: appName,
          dryRun: skipBuild
        )
      }
      bundlerContext.builtDependencies = dependencies

      if !skipBuild {
        if !productsDirectory.exists(withType: .directory) {
          try RichError<SwiftBundlerError>.catch {
            try FileManager.default.createDirectory(
              at: productsDirectory,
              withIntermediateDirectories: true
            )
          }
        }

        // Copy built depdencies
        if !dependencies.isEmpty {
          log.info("Copying dependencies")
        }

        for (_, dependency) in dependencies {
          guard
            dependency.product.type == .dynamicLibrary
              || dependency.product.type == .staticLibrary
          else {
            continue
          }

          for artifact in dependency.artifacts {
            try RichError<SwiftBundlerError>.catch {
              let destination = productsDirectory / artifact.location.lastPathComponent
              if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
              }

              try FileManager.default.copyItem(
                at: artifact.location,
                to: destination
              )
            }
          }
        }

        log.info("Starting \(buildContext.genericContext.configuration.rawValue) build")
        try await RichError<SwiftBundlerError>.catch {
          if isUsingXcodebuild {
            try await Xcodebuild.build(
              product: appConfiguration.product,
              buildContext: buildContext,
              destination: resolvedDevice
            )
          } else {
            try await SwiftPackageManager.build(
              product: appConfiguration.product,
              buildContext: buildContext
            )
          }
        }

        var executable = productsDirectory.appendingPathComponent(appConfiguration.product)
        if let fileExtension = resolvedPlatform.executableFileExtension {
          executable = executable.appendingPathExtension(fileExtension)
        }

        if resolvedPlatform == .linux {
          try await RichError<SwiftBundlerError>.catch {
            let debugInfoFile = originalExecutableArtifact.appendingPathExtension("debug")
            if debugInfoFile.exists() {
              try FileManager.default.removeItem(at: debugInfoFile)
            }
            try await Stripper.extractLinuxDebugInfo(
              from: originalExecutableArtifact,
              to: debugInfoFile
            )
          }
        }

        if arguments.strip {
          try await RichError<SwiftBundlerError>.catch {
            if executableArtifact.exists() {
              try FileManager.default.removeItem(at: executableArtifact)
            }
            try FileManager.default.copyItem(at: originalExecutableArtifact, to: executableArtifact)
            try await Stripper.strip(executableArtifact)
          }
        }
      }

      try Self.removeExistingOutputs(
        outputDirectory: outputDirectory,
        skip: [
          dependenciesScratchDirectory.lastPathComponent,
          metadataDirectory.lastPathComponent
        ]
      )

      return try await Self.bundle(
        with: arguments.bundler.bundler,
        context: bundlerContext,
        command: self,
        manifest: manifest
      )
    }

    if !dryRun {
      let bundle: URL
      if let copyOutDirectory = arguments.copyOutDirectory {
        bundle = copyOutDirectory.appendingPathComponent(
          bundlerOutputStructure.bundle.lastPathComponent
        )
        do {
          if bundle.exists() {
            try FileManager.default.removeItem(at: bundle)
          }
          try FileManager.default.copyItem(
            at: bundlerOutputStructure.bundle,
            to: bundle
          )
        } catch {
          throw RichError(SwiftBundlerError.failedToCopyOutBundle, cause: error)
        }
      } else {
        bundle = bundlerOutputStructure.bundle
      }

      // Output the time elapsed along with the location of the produced app bundle.
      log.info(
        """
        Done in \(elapsed.secondsString). App bundle located at \
        '\(bundle.relativePath)'
        """
      )
    }

    return bundlerOutputStructure
  }
  // swiftlint:enable cyclomatic_complexity

  /// Removes the given output directory if it exists.
  static func removeExistingOutputs(
    outputDirectory: URL,
    skip excludedItems: [String]
  ) throws(RichError<SwiftBundlerError>) {
    if outputDirectory.exists(withType: .directory) {
      do {
        let contents = try FileManager.default.contentsOfDirectory(
          at: outputDirectory,
          includingPropertiesForKeys: nil
        )
        for item in contents {
          guard !excludedItems.contains(item.lastPathComponent) else {
            continue
          }
          try FileManager.default.removeItem(at: item)
        }
      } catch {
        throw RichError(
          .failedToRemoveExistingOutputs(outputDirectory: outputDirectory),
          cause: error
        )
      }
    }
  }

  /// This generic function is required to operate on `any Bundler`s.
  static func bundle<B: Bundler>(
    with bundler: B.Type,
    context: BundlerContext,
    command: Self,
    manifest: PackageManifest
  ) async throws(RichError<SwiftBundlerError>) -> BundlerOutputStructure {
    try await RichError<SwiftBundlerError>.catch {
      let additionalContext = try bundler.computeContext(
        context: context,
        command: command,
        manifest: manifest
      )
      return try await bundler.bundle(context, additionalContext)
    }
  }

  /// This generic function is required to operate on `any Bundler`s.
  static func intendedOutput<B: Bundler>(
    of bundler: B.Type,
    context: BundlerContext,
    command: Self,
    manifest: PackageManifest
  ) throws(RichError<SwiftBundlerError>) -> BundlerOutputStructure {
    try RichError<SwiftBundlerError>.catch {
      let additionalContext = try bundler.computeContext(
        context: context,
        command: command,
        manifest: manifest
      )
      return bundler.intendedOutput(in: context, additionalContext)
    }
  }

  /// Gets the configuration for the specified app.
  ///
  /// If no app is specified, the first app is used (unless there are multiple
  /// apps, in which case an error is thrown).
  /// - Parameters:
  ///   - appName: The app's name.
  ///   - packageDirectory: The package's root directory.
  ///   - context: The context used to evaluate configuration overlays.
  ///   - customFile: A custom configuration file not at the standard location.
  /// - Returns: The app's configuration.
  static func getConfiguration(
    _ appName: String?,
    packageDirectory: URL,
    context: ConfigurationFlattener.Context,
    customFile: URL? = nil
  ) async throws(RichError<SwiftBundlerError>) -> (
    appName: String,
    appConfiguration: AppConfiguration.Flat,
    configuration: PackageConfiguration.Flat
  ) {
    if let configuration = Self.bundlerConfiguration {
      return configuration
    }

    return try await RichError<SwiftBundlerError>.catch {
      let configuration = try await PackageConfiguration.load(
        fromDirectory: packageDirectory,
        customFile: customFile
      )

      let flatConfiguration = try ConfigurationFlattener.flatten(
        configuration,
        with: context
      )

      let (appName, appConfiguration) = try flatConfiguration.getAppConfiguration(
        appName
      )

      Self.bundlerConfiguration = (appName, appConfiguration, flatConfiguration)
      return (appName, appConfiguration, flatConfiguration)
    }
  }

  static func outputDirectory(for scratchDirectory: URL) -> URL {
    scratchDirectory / "bundler"
  }
}
