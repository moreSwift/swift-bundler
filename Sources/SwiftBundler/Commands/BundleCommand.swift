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

  /// Prints the path of the output bundle and exits.
  @Flag(
    name: .long,
    help: """
      Print the path of the output bundle and exits. The bundle may not exist yet \
      if you haven't already performed a build.
      """
  )
  var showBundlePath = false

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
    showBundlePath: Bool,
    builtWithXcode: Bool,
    hotReloadingEnabled: Bool,
    verbose: Bool
  ) {
    _arguments = arguments
    self.skipBuild = skipBuild
    self.showBundlePath = showBundlePath
    self.builtWithXcode = builtWithXcode
    self.hotReloadingEnabled = hotReloadingEnabled
    self.verbose = verbose
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

    if let bundler = arguments.bundler {
      if !bundler.isSupportedOnHostPlatform {
        log.error(
          """
          The '\(arguments.bundler?.rawValue ?? "<unknown>")' bundler is not supported on the \
          current host platform. Supported bundlers: \
          \(BundlerChoice.supportedHostValuesDescription)
          """
        )
        return false
      }

      if !bundler.supportedTargetPlatforms.contains(platform) {
        let alternatives = BundlerChoice.allCases.filter { choice in
          choice.supportedTargetPlatforms.contains(platform)
        }
        let alternativesDescription = "(\(alternatives.map(\.rawValue).joined(separator: "|")))"
        log.error(
          """
          The '\(bundler.rawValue)' bundler doesn't support bundling \
          for '\(platform)'. Supported target platforms: \
          \(BundlerChoice.supportedHostValuesDescription). Valid alternative \
          bundlers: \(alternativesDescription)
          """
        )
        return false
      }
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

    if platform != .macOS && arguments.standAlone {
      log.error("'--experimental-stand-alone' only works when targeting macOS (and that excludes Mac Catalyst)")
      return false
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

  static func resolveCodeSigningContext(
    codesignArgument: Bool?,
    identityArgument: String?,
    provisioningProfile: URL?,
    entitlements: URL?,
    azureArtifactSigningMetadata: URL?,
    platform: Platform
  ) async throws(RichError<SwiftBundlerError>) -> (
    BundlerContext.DarwinCodeSigningContext?,
    BundlerContext.WindowsCodeSigningContext?
  ) {
    switch platform.partitioned {
      case .apple(let platform):
        let context = try await resolveDarwinCodeSigningContext(
          codesignArgument: codesignArgument,
          identityArgument: identityArgument,
          provisioningProfile: provisioningProfile,
          entitlements: entitlements,
          platform: platform
        )
        return (context, nil)
      case .windows:
        let context = try await resolveWindowsCodeSigningContext(
          codesignArgument: codesignArgument,
          identityArgument: identityArgument,
          provisioningProfile: provisioningProfile,
          entitlements: entitlements,
          azureArtifactSigningMetadata: azureArtifactSigningMetadata
        )
        return (nil, context)
      case .linux, .android:
        // Handle unsupported platforms
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
          throw RichError(SwiftBundlerError.failedToResolveCodeSigningConfiguration(reason: reason))
        }

        return (nil, nil)
    }
  }

  static func resolveWindowsCodeSigningContext(
    codesignArgument: Bool?,
    identityArgument: String?,
    provisioningProfile: URL?,
    entitlements: URL?,
    azureArtifactSigningMetadata: URL?
  ) async throws(RichError<SwiftBundlerError>) -> BundlerContext.WindowsCodeSigningContext? {
    guard entitlements == nil else {
      let reason = "Code signing entitlements aren't supported on Windows"
      throw RichError(SwiftBundlerError.failedToResolveCodeSigningConfiguration(reason: reason))
    }

    guard provisioningProfile == nil else {
      let reason = "Provisioning profiles aren't supported on Windows"
      throw RichError(SwiftBundlerError.failedToResolveCodeSigningConfiguration(reason: reason))
    }

    guard codesignArgument == true else {
      return nil
    }

    if let azureArtifactSigningMetadata {
      guard identityArgument == nil else {
        let reason = "--identity is incompatible with --azure-artifact-signing-metadata"
        throw RichError(SwiftBundlerError.failedToResolveCodeSigningConfiguration(reason: reason))
      }
      return BundlerContext.WindowsCodeSigningContext.azureArtifactSigning(
        metadata: azureArtifactSigningMetadata
      )
    }

    let identity: CodeSigningIdentity
    if let searchTerm = identityArgument {
      identity = try RichError<SwiftBundlerError>.catch {
        try WindowsCodeSigner.resolveIdentity(searchTerm: searchTerm)
      }
    } else {
      let identities = try RichError<SwiftBundlerError>.catch {
        try WindowsCodeSigner.enumerateIdentities()
      }
      guard let match = identities.first else {
        let reason = """
          No code signing identities found. If you created a self-signed \
          certificate ensure that it has code signing as a valid usage listed \
          in its EKU field.
          """
        throw RichError(SwiftBundlerError.failedToResolveCodeSigningConfiguration(reason: reason))
      }
      if identities.count > 1 {
        log.warning(
          """
          Found multiple code signing identities, using \(match); list all available \
          identities using 'swift-bundler list-identities' and provide the '--identity' \
          option to select a particular identity
          """
        )
      }
      identity = match
    }

    return BundlerContext.WindowsCodeSigningContext.localCertificate(identity: identity)
  }

  static func resolveDarwinCodeSigningContext(
    codesignArgument: Bool?,
    identityArgument: String?,
    provisioningProfile: URL?,
    entitlements: URL?,
    platform: ApplePlatform
  ) async throws(RichError<SwiftBundlerError>) -> BundlerContext.DarwinCodeSigningContext? {
    let codesign: Bool
    if platform.requiresProvisioningProfiles {
      if codesignArgument == nil || codesignArgument == true {
        codesign = true
      } else {
        let reason = """
          \(platform.platform.name) is incompatible with '--no-codesign' \
          because it requires provisioning profiles
          """
        throw RichError(SwiftBundlerError.failedToResolveCodeSigningConfiguration(reason: reason))
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
        throw RichError(SwiftBundlerError.failedToResolveCodeSigningConfiguration(reason: reason))
      }
      return nil
    }

    do {
      let identity: CodeSigningIdentity
      if let identityShortName = identityArgument {
        identity = try await RichError<SwiftBundlerError>.catch {
          try await DarwinCodeSigner.resolveIdentity(shortName: identityShortName)
        }
      } else {
        let identities = try await RichError<SwiftBundlerError>.catch {
          try await DarwinCodeSigner.enumerateIdentities()
        }

        guard let firstIdentity = identities.first else {
          let reason = """
            No codesigning identities found. Please sign into Xcode and try again.
            """
          throw RichError(SwiftBundlerError.failedToResolveCodeSigningConfiguration(reason: reason))
        }

        if identities.count > 1 {
          log.warning("Multiple codesigning identities found; using '\(firstIdentity)'")
          log.debug("Other identities: \(identities)")
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
      if let platform = platform, !platform.hasSimulator {
        let reason = "'--simulator' is incompatible with '--platform \(platform)'"
        throw RichError(SwiftBundlerError.failedToResolveTargetDevice(reason: reason))
      }

      let matchingSimulators = try await RichError<SwiftBundlerError>.catch {
        try await SimulatorManager.listSimulators(
          searchTerm: simulatorSpecifier
        )
      }.sorted().filter { simulator in
        // Filter by platform if platform hint provided
        if let platform = platform {
          return simulator.os.os == platform.os
        } else {
          return true
        }
      }

      guard let simulator = matchingSimulators.first else {
        let platformCondition = platform.map { " with platform '\($0)'" } ?? ""
        let reason = """
          No simulator found matching '\(simulatorSpecifier)'\(platformCondition). Use \
          'swift bundler simulators list' to list available simulators.
          """
        throw RichError(SwiftBundlerError.failedToResolveTargetDevice(reason: reason))
      }

      if matchingSimulators.count > 1 {
        log.warning(
          "Multiple simulators matched '\(simulatorSpecifier)'; using '\(simulator.name)'"
        )
        log.debug("Matching simulators: \(matchingSimulators)")
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
          let matchingSimulators = try await RichError<SwiftBundlerError>.catch {
            try await AppleSimulatorManager.listAvailableSimulators()
          }.filter { simulator in
            simulator.isBooted
              && simulator.isAvailable
              && simulator.os.os == platform.os
          }.sorted()

          guard let simulator = matchingSimulators.first else {
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

          if matchingSimulators.count > 1 {
            log.warning(
              "Found multiple booted \(platform.os.rawValue) simulators, using '\(simulator.name)'"
            )
            log.debug("Matching simulators: \(matchingSimulators)")
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

  /// Gets the architectures to use for the current build. Validates the '--arch'
  /// arguments passed in by the user.
  func getArchitectures(platform: Platform, device: Device?)
    async throws(RichError<SwiftBundlerError>) -> [BuildArchitecture]
  {
    guard !arguments.universal || platform.supportsMultiArchitectureBuilds else {
      let message = SwiftBundlerError.platformDoesNotSupportMultiArchitectureBuilds(
        platform,
        universalFlag: true
      )
      throw RichError(message)
    }

    let supportedArchitectures = platform.supportedCompilationArchitectures
    let architectures = arguments.universal ? supportedArchitectures : arguments.architectures
    guard !architectures.isEmpty else {
      return [platform.defaultCompilationArchitecture(.host)]
    }

    var unsupportedArchitectures: [BuildArchitecture] = []
    for architecture in architectures {
      if !supportedArchitectures.contains(architecture) {
        unsupportedArchitectures.append(architecture)
      }
    }

    guard unsupportedArchitectures.isEmpty else {
      throw RichError(.unsupportedTargetArchitectures(unsupportedArchitectures, platform))
    }

    guard architectures.count == 1 || platform.supportsMultiArchitectureBuilds else {
      let message = SwiftBundlerError.platformDoesNotSupportMultiArchitectureBuilds(
        platform,
        universalFlag: false
      )
      throw RichError(message)
    }

    if let device, case .androidDevice(let androidDevice) = device {
      let architecture = try await RichError<SwiftBundlerError>.catch {
        let androidDevice = AndroidDebugBridge.ConnectedDevice(
          identifier: androidDevice.id
        )
        return try await AndroidDebugBridge.getArchitecture(of: androidDevice)
      }

      guard architectures.contains(architecture) else {
        throw RichError(.deviceArchitectureMismatch(
          device,
          architecture,
          architectures
        ))
      }
    }

    return architectures
  }

  func resolveContext() async throws(RichError<SwiftBundlerError>) -> BundleCommandContext {
    let (platform, device) = try await Self.resolvePlatform(
      platform: arguments.platform,
      deviceSpecifier: arguments.deviceSpecifier,
      simulatorSpecifier: arguments.simulatorSpecifier
    )

    let bundler = arguments.bundler
      ?? BundlerChoice.defaultForTargetPlatform(platform)

    let architectures = try await getArchitectures(platform: platform, device: device)
    let configurationFlattenerContext = ConfigurationFlattener.Context(
      platform: platform,
      bundler: bundler,
      architectures: architectures
    )

    let packageDirectory = arguments.packageDirectory ?? URL.currentDirectory

    let (appName, appConfiguration, configuration) = try await Self.getConfiguration(
      arguments.appName,
      packageDirectory: packageDirectory,
      context: configurationFlattenerContext,
      customFile: arguments.configurationFileOverride
    )

    let (toolchain, swiftSDK) = try await resolveSwiftToolchain(
      resolvedPlatform: platform,
      architectures: architectures,
      androidMinSDK: appConfiguration.androidMinSDKOrDefault
    )
    
    if !showBundlePath {
      log.info("Loading package manifest")
    }
    let manifest = try await RichError<SwiftBundlerError>.catch {
      try await SwiftPackageManager.loadPackageManifest(
        from: packageDirectory,
        toolchain: toolchain
      )
    }

    let platformVersion = platform.platformVersion(
      from: manifest,
      appConfiguration: appConfiguration
    )

    return BundleCommandContext(
      packageDirectory: packageDirectory,
      manifest: manifest,
      configuration: configuration,
      appName: appName,
      appConfiguration: appConfiguration,
      configurationFlattenerContext: configurationFlattenerContext,
      platform: platform,
      platformVersion: platformVersion,
      architectures: architectures,
      device: device,
      bundler: bundler,
      toolchain: toolchain,
      swiftSDK: swiftSDK
    )
  }

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    let context = try await resolveContext()
    _ = try await doBundling(context: context)
  }

  func resolveSwiftToolchain(
    resolvedPlatform: Platform,
    architectures: [BuildArchitecture],
    androidMinSDK: Int?
  ) async throws(RichError<SwiftBundlerError>) -> (URL?, SwiftSDK?) {
    // Resolve toolchain
    var resolvedToolchain = arguments.toolchain
    let swiftSDK: SwiftSDK?
    if resolvedPlatform == .android {
      guard let androidMinSDK else {
        throw RichError<SwiftBundlerError>(
          .cannotResolveSwiftToolchainForAndroidWithoutMinSDK
        )
      }

      // TODO(stackotter): Refactor SwiftPackageManager so that we can
      //   resolve the Swift Android SDK once and pass it into each
      //   piece of code that needs it.
      let targetTriple = try RichError<SwiftBundlerError>.catch {
        try resolvedPlatform.targetTriple(
          withArchitecture: architectures[0],
          andPlatformVersion: String(androidMinSDK)
        )
      }

      let androidSDK = try RichError<SwiftBundlerError>.catch {
        try SwiftSDKManager.locateSDKMatching(
          hostPlatform: .hostPlatform,
          hostArchitecture: .host,
          targetTriple: targetTriple
        )
      }
      swiftSDK = androidSDK

      log.info("Using Swift Android SDK at '\(androidSDK.bundle.path)'")

      if resolvedToolchain == nil {
        do {
          let toolchain = try await SwiftToolchainManager.locateSwiftToolchain(
            compatibleWithAndroidSDK: androidSDK
          ).root

          resolvedToolchain = toolchain

          log.info("Found compatible Swift toolchain at '\(toolchain.path)'")
        } catch {
          log.warning(
            """
            Failed to resolve compatible toolchain to use for Android: \
            \(chainDescription(for: error, verbose: verbose))
            """
          )
        }
      }
    } else {
      swiftSDK = nil
    }

    return (resolvedToolchain, swiftSDK)
  }

  // swiftlint:disable cyclomatic_complexity
  /// - Parameters
  ///   - context: The context required to do bundling.
  ///   - dryRun: During a dry run, all of the validation steps are
  ///     performed without performing any side effects. This allows the
  ///     `RunCommand` to figure out where the output bundle will end up even
  ///     when the user instructs it to skip bundling.
  /// - Returns: A description of the structure of the bundler's output.
  func doBundling(
    context: BundleCommandContext,
    dryRun: Bool = false
  ) async throws(RichError<SwiftBundlerError>) -> BundlerOutputStructure {
    let (resolvedDarwinCodeSigningContext, resolvedWindowsCodeSigningContext) =
      try await Self.resolveCodeSigningContext(
        codesignArgument: arguments.codesign,
        identityArgument: arguments.identity,
        provisioningProfile: arguments.provisioningProfile,
        entitlements: arguments.entitlements,
        azureArtifactSigningMetadata: arguments.azureArtifactSigningMetadata,
        platform: context.platform
      )

    try RichError<SwiftBundlerError>.catch {
      try context.bundler.bundler.checkHostCompatibility()
    }

    guard
      Self.validateArguments(
        arguments,
        platform: context.platform,
        skipBuild: skipBuild,
        builtWithXcode: builtWithXcode
      )
    else {
      Foundation.exit(1)
    }

    // Time execution so that we can report it to the user.
    let (elapsed, bundlerOutputStructure) = try await Stopwatch.time { () async throws(RichError<SwiftBundlerError>) in
      // Load configuration
      let scratchDirectory =
        arguments.scratchDirectory ?? (context.packageDirectory / ".build")

      guard
        Self.validateArguments(
          arguments,
          platform: context.platform,
          skipBuild: skipBuild,
          builtWithXcode: builtWithXcode
        )
      else {
        Foundation.exit(1)
      }

      // Whether or not we are building with xcodebuild instead of swiftpm.
      let isUsingXcodebuild = Xcodebuild.isUsingXcodebuild(
        for: self,
        resolvedPlatform: context.platform
      )

      if isUsingXcodebuild {
        // Terminate the program if the project is an Xcodeproj based project.
        let xcodeprojs = try RichError<SwiftBundlerError>.catch {
          try FileManager.default.contentsOfDirectory(
            at: context.packageDirectory,
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
      let appOutputDirectory = outputDirectory / "apps" / context.appName

      let metadataDirectory = appOutputDirectory / "metadata"
      if !metadataDirectory.exists() {
        try RichError<SwiftBundlerError>.catch {
          try FileManager.default.createDirectory(
            at: metadataDirectory,
            withIntermediateDirectories: true
          )
        }
      }

      // TODO: Support metadata compilation on Android. The main issue is that
      //   -Xlinker flags get passed to macro/plugin builds in addition to the
      //   app's main product build, leading to errors where we end up trying
      //   to link the metadata into macOS executables (which obviously fails).
      //   I'm not sure how we can work around that issue without SwiftPM
      //   modifications. Maybe we can compile the metadata to a static library
      //   then do something similar to swift-sentry where we create a systemLibrary
      //   that links to the library by name, and Swift Bundler can place the
      //   compiled metadata library into `.build/<config>` before starting the
      //   build so that SwiftPM finds it.
      let compiledMetadata: MetadataInserter.CompiledMetadata?
      if context.platform != .android {
        compiledMetadata = try await RichError<SwiftBundlerError>.catch {
          return try await MetadataInserter.compileMetadata(
            in: metadataDirectory,
            for: MetadataInserter.metadata(for: context.appConfiguration),
            architectures: context.architectures,
            platform: context.platform,
            swiftToolchain: context.toolchain,
            swiftSDK: context.swiftSDK,
            dryRun: dryRun || showBundlePath
          )
        }
      } else {
        compiledMetadata = nil
      }

      let buildContext = SwiftPackageManager.BuildContext(
        genericContext: GenericBuildContext(
          projectDirectory: context.packageDirectory,
          scratchDirectory: scratchDirectory,
          configuration: arguments.buildConfiguration,
          architectures: context.architectures,
          platform: context.platform,
          platformVersion: context.platformVersion,
          additionalArguments: isUsingXcodebuild
            ? arguments.additionalXcodeBuildArguments
            : arguments.additionalSwiftPMArguments
        ),
        toolchain: context.toolchain,
        hotReloadingEnabled: hotReloadingEnabled,
        isGUIExecutable: true,
        compiledMetadata: compiledMetadata,
        swiftSDK: context.swiftSDK
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
        let archString = context.architectures.compactMap({ $0.rawValue })
          .joined(separator: "_")

        // xcodebuild adds a platform suffix to the products directory for
        // certain platforms. E.g. it's 'Release-xrsimulator' for visionOS.
        let productsDirectoryBase = arguments.buildConfiguration.rawValue.capitalized
        let swiftpmSuffix: String
        let xcodeSuffix: String
        if let suffix = context.platform.xcodeProductDirectorySuffix {
          xcodeSuffix = "-\(suffix)"
          swiftpmSuffix = suffix
        } else {
          xcodeSuffix = ""
          swiftpmSuffix = context.platform.rawValue
        }
        productsDirectory =
          arguments.productsDirectory
          ?? (context.packageDirectory
            / ".build/\(archString)-apple-\(swiftpmSuffix)"
            / "Build/Products/\(productsDirectoryBase)\(xcodeSuffix)")
      }

      var originalExecutableArtifact = productsDirectory / context.appConfiguration.product
      if let fileExtension = context.platform.executableFileExtension {
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
        appName: context.appName,
        packageName: context.manifest.name,
        appConfiguration: context.appConfiguration,
        packageDirectory: context.packageDirectory,
        productsDirectory: productsDirectory,
        outputDirectory: appOutputDirectory,
        packageGraph: SwiftPackageManager.PackageGraph.dummy,
        architectures: buildContext.genericContext.architectures,
        platform: context.platform,
        platformVersion: context.platformVersion,
        device: context.device,
        darwinCodeSigningContext: resolvedDarwinCodeSigningContext,
        windowsCodeSigningContext: resolvedWindowsCodeSigningContext,
        builtDependencies: [:],
        executableArtifact: executableArtifact,
        swiftToolchain: context.toolchain,
        swiftSDK: context.swiftSDK
      )

      // If the user has requested the bundle path, print it and exit.
      if showBundlePath {
        let output = try Self.intendedOutput(
          of: context.bundler.bundler,
          context: bundlerContext,
          command: self,
          manifest: context.manifest
        )
        print(output.bundle.path)
        Foundation.exit(0)
      }

      // If this is a dry run, drop out just before we start actually do stuff.
      guard !dryRun else {
        return try Self.intendedOutput(
          of: context.bundler.bundler,
          context: bundlerContext,
          command: self,
          manifest: context.manifest
        )
      }

      let packageGraph = try await RichError<SwiftBundlerError>.catch {
        try await SwiftPackageManager.loadPackageGraph(
          packageDirectory: context.packageDirectory,
          configurationContext: context.configurationFlattenerContext,
          toolchain: context.toolchain
        )
      }
      bundlerContext.packageGraph = packageGraph

      let dependenciesScratchDirectory = outputDirectory / "projects"

      var dependencyContext = buildContext.genericContext
      dependencyContext.scratchDirectory = dependenciesScratchDirectory
      let dependencies = try await RichError<SwiftBundlerError>.catch {
        try await ProjectBuilder.buildDependencies(
          appConfiguration: context.appConfiguration,
          packageConfiguration: context.configuration,
          packageGraph: packageGraph,
          context: dependencyContext,
          swiftToolchain: context.toolchain,
          appName: context.appName,
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
            guard !context.bundler.bundler.requiresBuildAsDylib else {
              throw SwiftBundlerError.xcodeCannotBuildAsDylib
            }
            try await Xcodebuild.build(
              product: context.appConfiguration.product,
              buildContext: buildContext,
              destination: context.device
            )
          } else {
            // This function exists to unwrap the existential 'any Bundler.Type'
            func prepareArgumentsFromBundler<T: Bundler>(_ bundler: T.Type)
              async throws(RichError<SwiftBundlerError>) -> [String]
            {
              try await RichError<SwiftBundlerError>.catch {
                try await bundler.prepareAdditionalSPMBuildArguments(
                  bundlerContext,
                  try bundler.computeContext(
                    context: bundlerContext,
                    command: self,
                    manifest: context.manifest
                  ),
                  dryRun: dryRun
                )
              }
            }

            let bundler = context.bundler.bundler
            let additionalArgumentsFromBundler = try await prepareArgumentsFromBundler(bundler)

            // These arguments only apply to the main executable, so we're safe to
            // add them to the build context this late in the build process (after
            // dependencies etc)
            var buildContext = buildContext
            buildContext.genericContext.additionalArguments += additionalArgumentsFromBundler

            if context.bundler.bundler.requiresBuildAsDylib {
              _ = try await SwiftPackageManager.buildExecutableAsDylib(
                product: context.appConfiguration.product,
                buildContext: buildContext
              )
            } else {
              try await SwiftPackageManager.build(
                product: context.appConfiguration.product,
                buildContext: buildContext
              )
            }
          }
        }

        var executable = productsDirectory / context.appConfiguration.product
        if let fileExtension = context.platform.executableFileExtension {
          executable = executable.appendingPathExtension(fileExtension)
        }

        if context.platform == .linux {
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
        outputDirectory: appOutputDirectory,
        skip: [metadataDirectory.lastPathComponent]
      )

      return try await Self.bundle(
        with: context.bundler.bundler,
        context: bundlerContext,
        command: self,
        manifest: context.manifest
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
