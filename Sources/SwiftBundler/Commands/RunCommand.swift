import ArgumentParser
import ErrorKit
import Foundation

#if SUPPORT_HOT_RELOADING
  import FileSystemWatcher
  import HotReloadingProtocol
  import FlyingSocks
#endif

/// The subcommand for running an app from a package.
struct RunCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "run",
    abstract: "Run a package as an app."
  )

  /// Arguments in common with the bundle command.
  @OptionGroup
  var arguments: BundleArguments

  /// A file containing environment variables to pass to the app.
  @Option(
    name: [.customLong("env")],
    help: "A file containing environment variables to pass to the app.",
    transform: URL.init(fileURLWithPath:))
  var environmentFile: URL?

  /// If `true`, the building and bundling step is skipped.
  @Flag(
    name: .long,
    help: "Skips the building and bundling steps.")
  var skipBuild = false

  /// If `true`, the app gets rebuilt whenever code changes occur, and a hot reloading server is
  /// hosted in the background to notify the running app of the new build.
  @Flag(name: .long, help: "Enables hot reloading.")
  var hot = false

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages.")
  public var verbose = false

  /// Command line arguments that get passed through to the app.
  @Argument(
    parsing: .postTerminator,
    help: "Command line arguments to pass through to the app.")
  var passThroughArguments: [String] = []

  // MARK: Methods

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    guard !(skipBuild && hot) else {
      log.error("'--skip-build' is incompatible with '--hot' (nonsensical)")
      Foundation.exit(1)
    }

    #if !SUPPORT_HOT_RELOADING
      if hot {
        log.error(
          """
          This build of Swift Bundler doesn't support hot reloading. Only macOS \
          and Linux builds support hot reloading.
          """
        )
        Foundation.exit(1)
      }
    #endif

    // Load configuration
    let packageDirectory = arguments.packageDirectory ?? URL.currentDirectory
    let scratchDirectory = arguments.scratchDirectory ?? packageDirectory / ".build"

    let device = try await BundleCommand.resolveDevice(
      platform: arguments.platform,
      deviceSpecifier: arguments.deviceSpecifier,
      simulatorSpecifier: arguments.simulatorSpecifier
    )

    let resolvedBundler = arguments.bundler
      ?? BundlerChoice.defaultForTargetPlatform(device.platform)

    guard resolvedBundler.bundler.outputIsRunnable else {
      log.error(
        """
        The chosen bundler (\(resolvedBundler.rawValue)) is bundling-only \
        (i.e. it doesn't output a runnable bundle). Choose a different bundler \
        or stick to bundling and manually install the bundle on your system to \
        run your app.
        """
      )
      Foundation.exit(1)
    }

    let (_, appConfiguration, _) = try await BundleCommand.getConfiguration(
      arguments.appName,
      packageDirectory: packageDirectory,
      context: ConfigurationFlattener.Context(
        platform: device.platform,
        bundler: resolvedBundler
      ),
      customFile: arguments.configurationFileOverride
    )

    let bundleCommand = BundleCommand(
      arguments: _arguments,
      skipBuild: false,
      builtWithXcode: false,
      hotReloadingEnabled: hot
    )

    // Perform bundling, or do a dry run if instructed to skip building (so
    // that we still know where the output bundle is located).
    let bundlerOutput = try await bundleCommand.doBundling(
      dryRun: skipBuild,
      resolvedPlatform: device.platform,
      resolvedBundler: resolvedBundler,
      resolvedDevice: device
    )

    let environmentVariables = try RichError<SwiftBundlerError>.catch {
      try environmentFile.map { file in
        try Runner.loadEnvironmentVariables(from: file)
      } ?? [:]
    }

    // TODO: Avoid loading manifest twice
    let manifest = try await RichError<SwiftBundlerError>.catch {
      try await SwiftPackageManager.loadPackageManifest(
        from: packageDirectory,
        toolchain: arguments.toolchain
      )
    }

    let platformVersion = device.platform.platformVersion(from: manifest)
    let architectures = try bundleCommand.getArchitectures(
      platform: device.platform
    )

    let additionalEnvironmentVariables: [String: String]
    #if SUPPORT_HOT_RELOADING
      if hot {
        let buildContext = GenericBuildContext(
          projectDirectory: packageDirectory,
          scratchDirectory: scratchDirectory,
          configuration: arguments.buildConfiguration,
          architectures: architectures,
          platform: device.platform,
          platformVersion: platformVersion,
          additionalArguments: arguments.additionalSwiftPMArguments
        )

        // Start server and file system watcher (integrated into server)
        let server = try await RichError<SwiftBundlerError>.catch {
          try await HotReloadingServer.create()
        }

        Task {
          do {
            try await server.start(
              product: appConfiguration.product,
              buildContext: buildContext,
              swiftToolchain: arguments.toolchain,
              appConfiguration: appConfiguration
            )
          } catch {
            log.error(
              "Failed to start hot reloading server: \(ErrorKit.userFriendlyMessage(for: error))"
            )
          }
        }

        additionalEnvironmentVariables = [
          "SWIFT_BUNDLER_HOT_RELOADING": "1",
          "SWIFT_BUNDLER_SERVER": "127.0.0.1:\(server.port)",
        ]
      } else {
        additionalEnvironmentVariables = [:]
      }
    #else
      additionalEnvironmentVariables = [:]
    #endif

    try await RichError<SwiftBundlerError>.catch {
      try await Runner.run(
        bundlerOutput: bundlerOutput,
        bundleIdentifier: appConfiguration.identifier,
        device: device,
        arguments: passThroughArguments,
        environmentVariables: environmentVariables.merging(
          additionalEnvironmentVariables, uniquingKeysWith: { key, _ in key }
        )
      )
    }
  }
}
