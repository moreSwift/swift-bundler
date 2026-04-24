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

    let bundleCommand = BundleCommand(
      arguments: _arguments,
      skipBuild: false,
      showBundlePath: false,
      builtWithXcode: false,
      hotReloadingEnabled: hot,
      verbose: verbose
    )

    let context = try await bundleCommand.resolveContext()

    guard context.bundler.bundler.outputIsRunnable else {
      log.error(
        """
        The chosen bundler (\(context.bundler.rawValue)) is bundling-only \
        (i.e. it doesn't output a runnable bundle). Choose a different bundler \
        or stick to bundling and manually install the bundle on your system to \
        run your app.
        """
      )
      Foundation.exit(1)
    }

    let device: Device
    if let contextDevice = context.device {
      device = contextDevice
    } else {
      device = try await BundleCommand.resolveDevice(
        platform: context.platform,
        deviceSpecifier: arguments.deviceSpecifier,
        simulatorSpecifier: arguments.simulatorSpecifier
      )
    }

    // Perform bundling, or do a dry run if instructed to skip building (so
    // that we still know where the output bundle is located).
    let bundlerOutput = try await bundleCommand.doBundling(
      context: context,
      dryRun: skipBuild
    )

    let environmentVariables = try RichError<SwiftBundlerError>.catch {
      try environmentFile.map { file in
        try Runner.loadEnvironmentVariables(from: file)
      } ?? [:]
    }

    let additionalEnvironmentVariables: [String: String]
    #if SUPPORT_HOT_RELOADING
      if hot {
        let buildContext = GenericBuildContext(
          projectDirectory: packageDirectory,
          scratchDirectory: scratchDirectory,
          configuration: arguments.buildConfiguration,
          architectures: context.architectures,
          platform: device.platform,
          platformVersion: context.platformVersion,
          additionalArguments: arguments.additionalSwiftPMArguments
        )

        // Start server and file system watcher (integrated into server)
        let server = try await RichError<SwiftBundlerError>.catch {
          try await HotReloadingServer.create()
        }

        Task {
          do {
            try await server.start(
              product: context.appConfiguration.product,
              buildContext: buildContext,
              swiftToolchain: context.toolchain,
              swiftSDK: context.swiftSDK,
              appConfiguration: context.appConfiguration
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
        bundleIdentifier: context.appConfiguration.identifier,
        device: device,
        arguments: passThroughArguments,
        environmentVariables: environmentVariables.merging(
          additionalEnvironmentVariables, uniquingKeysWith: { key, _ in key }
        )
      )
    }
  }
}
