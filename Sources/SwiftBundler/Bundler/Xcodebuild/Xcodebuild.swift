import ArgumentParser
import Foundation
import Parsing
import Version
import Yams

/// A utility for interacting with xcodebuild.
enum Xcodebuild {
  /// Builds the specified product using a Swift package target as an xcodebuild scheme.
  /// - Parameters:
  ///   - product: The product to build.
  ///   - buildContext: The context to build in.
  ///   - destination: The destination to build for.
  /// - Returns: If an error occurs, returns a failure.
  static func build(
    product: String,
    buildContext: SwiftPackageManager.BuildContext,
    destination: Device?
  ) async throws(Error) {
    guard let applePlatform = buildContext.genericContext.platform.asApplePlatform else {
      throw Error(.unsupportedPlatform(buildContext.genericContext.platform))
    }

    let scheme =
      buildContext.genericContext.projectDirectory
      / ".swiftpm/xcode/xcshareddata/xcschemes/\(product).xcscheme"

    let cleanup: (() -> Void)?
    if scheme.exists() {
      let temporaryScheme = FileManager.default.temporaryDirectory / "\(UUID().uuidString).xcscheme"

      do {
        try FileManager.default.moveItem(at: scheme, to: temporaryScheme)
      } catch {
        throw Error(
          .failedToMoveInterferingScheme(
            scheme,
            destination: temporaryScheme
          ),
          cause: error
        )
      }

      cleanup = {
        do {
          try FileManager.default.moveItem(at: temporaryScheme, to: scheme)
        } catch {
          let relativePath = scheme.path(relativeTo: URL(fileURLWithPath: "."))
          log.warning(
            """
            Failed to restore xcscheme to \(relativePath). You may need to \
            re-run 'swift bundler generate-xcode-support' if you use \
            Xcode to build your project.
            """
          )
        }
      }
    } else {
      cleanup = nil
    }

    defer {
      cleanup?()
    }

    let pipe = Pipe()
    let process: Process

    let useXCBeautify = ProcessInfo.processInfo.bundlerEnvironment.useXCBeautify
    let xcbeautifyProcess: Process?
    if useXCBeautify {
      do {
        let xcbeautifyCommand = try await Process.locate("xcbeautify")
        xcbeautifyProcess = Process.create(
          xcbeautifyCommand,
          arguments: [
            "--disable-logging",
            "--preserve-unbeautified",
          ],
          directory: buildContext.genericContext.projectDirectory,
          runSilentlyWhenNotVerbose: false
        )
      } catch {
        xcbeautifyProcess = nil
      }
    } else {
      xcbeautifyProcess = nil
    }

    let context = buildContext.genericContext

    let destinationSpecifier = try await computeDestinationSpecifier(
      platform: applePlatform,
      architectures: context.architectures,
      destination: destination
    )
    let destinationArguments = ["-destination", destinationSpecifier]

    let metadataArguments: [String]
    if let compiledMetadata = buildContext.compiledMetadata {
      metadataArguments = MetadataInserter.additionalXcodebuildArguments(
        toInsert: compiledMetadata
      )
    } else {
      metadataArguments = []
    }

    let archString = context.architectures
      .map(\.rawValue)
      .joined(separator: "_")
    let suffix = context.platform.xcodeProductDirectorySuffix ?? context.platform.rawValue
    process = Process.create(
      "xcodebuild",
      arguments: [
        "-scheme", product,
        "-configuration", context.configuration.rawValue.capitalized,
        "-usePackageSupportBuiltinSCM",
        "-skipMacroValidation",
        "-derivedDataPath",
        context.projectDirectory.appendingPathComponent(
          ".build/\(archString)-apple-\(suffix)"
        ).path,
      ]
      + destinationArguments
      + context.additionalArguments
      + metadataArguments,
      directory: context.projectDirectory,
      runSilentlyWhenNotVerbose: false
    )

    if buildContext.hotReloadingEnabled {
      process.addEnvironmentVariables([
        "SWIFT_BUNDLER_HOT_RELOADING": "1"
      ])
    }

    // pipe xcodebuild output to xcbeautify.
    if let xcbeautifyProcess = xcbeautifyProcess {
      process.standardOutput = pipe
      xcbeautifyProcess.standardInput = pipe

      do {
        try xcbeautifyProcess.runAndLog()
      } catch {
        log.warning("xcbeautify error: \(error)")
      }
    }

    do {
      try await process.runAndWait()
    } catch {
      throw Error(
        .failedToRunXcodebuild( command: "Failed to run xcodebuild."),
        cause: error
      )
    }
  }

  /// Computes the xcodebuild destination specifier required to perform a build
  /// with the given target parameters.
  static func computeDestinationSpecifier(
    platform: ApplePlatform,
    architectures: [BuildArchitecture],
    destination: Device?
  ) async throws(Error) -> String {
    // NOTE: The reason that this code is complicated is that xcodebuild doesn't let
    //   us build without a destination, and destinations are either specific
    //   devices/simulators (single architecture by definition), or generic destinations
    //   (which are universal builds targeting all architectures supported by the target
    //   platform). We aren't able to specify architectures directly because xcodebuild
    //   doesn't allow `-arch` with `-destination`, and can't build SwiftPM packages without
    //   `-destination`. Kinda sucks...

    let supportedArchitectures = platform.supportedArchitectures
    for architecture in architectures {
      guard supportedArchitectures.contains(architecture) else {
        throw Error(.unsupportedArchitecture(platform, architecture))
      }
    }

    var destinationString: String
    let platformName = platform.xcodeDestinationName
    if architectures.count == 1 {
      // 1. If only one architecture, perform a single architecture build
      let architecture = architectures[0]
      if supportedArchitectures.count == 1 {
        // 1.1. If the target platform only supports one architecture, then
        //   we can use a generic destination (which is ideal because it
        //   means that you can still build even if the target device is
        //   unavailable due to being unlocked etc).
        destinationString = "generic/platform=\(platformName)"
      } else if let destinationId = destination?.id {
        // 1.2. If we have a device then that's easy
        destinationString = "id=\(destinationId),arch=\(architecture)"
      } else if [.macOS, .macCatalyst].contains(platform) {
        // TODO: Does this work when targeting a non-host architecture?
        // 1.3. If we're on macOS then it's also easy
        destinationString = "platform=\(platformName),arch=\(architecture)"
      } else {
        if platform.isSimulator {
          // 1.4.1. If we're targeting a simulator platform it gets annoying.
          //   xcodebuild's generic simulator destinations perform universal
          //   builds and don't let us override the architecture set, so we
          //   have to select a target simulator.
          let simulators = try await Error.catch {
            try await SimulatorManager.listAvailableSimulators()
          }

          let matchingSimulators = simulators.filter { simulator in
            // os os os, oi oi oi
            simulator.os.os == platform.os
          }

          guard let simulator = matchingSimulators.first else {
            throw Error(.failedToLocateSuitableDestinationSimulator(
              simulators,
              platform.os,
              architecture
            ))
          }

          destinationString = "id=\(simulator.id),arch=\(architecture)"
        } else {
          // 1.4.2. If we're targeting a physical non-macOS Apple device, then we
          //   assume that there's only a single supported architecture, so we should
          //   have reached 1.1. Therefore reaching this is an error.
          throw Error(cause: InvariantFailure(
            """
            Invariant failure: Swift Bundler assumes that non-macOS Apple platforms \
            each support only a single architecture (when not targeting a simulator). \
            Platform '\(platform)' supports '\(supportedArchitectures)'
            """
          ))
        }
      }
    } else if architectures == supportedArchitectures {
      // 2. If the set of architectures matches our target platform's supported
      //   architectures, then we can simply use a generic destination to perform
      //   a universal build.
      switch destination {
        case .host, .macCatalyst, nil:
          break
        case .connected:
          throw Error(.universalBuildIncompatibleWithConcreteDestination)
      }

      destinationString = "generic/platform=\(platformName)"
    } else {
      // 3. xcodebuild doesn't let us specify arbitrary sets of architectures when
      //   building Swift packages, but luckily we don't have to because this should
      //   be unreachable (unless a future Apple platform breaks out assumptions about
      //   Apple platform architecture support).
      throw Error(cause: InvariantFailure(
        """
        Invariant failure: xcodebuild can either build for a single architecture, or for all \
        supported architectures, but not in between; selected architectures were \
        \(architectures), supported architectures are '\(supportedArchitectures)'. \
        This is an invariant failure; we generally assume that each Apple platform \
        supports a maximum of 2 architectures. Please open an issue at \
        \(SwiftBundler.gitURL.absoluteString)/issues/new
        """
      ))
    }
    
    // Don't forget the variant!
    if let variant = platform.xcodeDestinationVariant {
      destinationString += ",variant=\(variant)"
    }

    return destinationString
  }

  /// Whether or not the bundle command utilizes xcodebuild instead of swiftpm.
  /// - Parameters:
  ///   - command: The subcommand for creating app bundles for a package.
  ///   - resolvedPlatform: The resolved target platform.
  /// - Returns: Whether or not xcodebuild is invoked instead of swiftpm.
  static func isUsingXcodebuild(
    for command: BundleCommand,
    resolvedPlatform: Platform
  ) -> Bool {
    var forceUsingXcodebuild = command.arguments.xcodebuild
    // For non-macOS Apple platforms (e.g. iOS) we default to using the
    // xcodebuild builder instead of SwiftPM because SwiftPM doesn't
    // properly support cross-compiling to other Apple platforms from
    // macOS (and the workaround Swift Bundler uses to do so breaks down
    // when the package uses macros or has conditional dependencies in
    // its Package.swift). This includes Mac Catalyst as well.
    let platformBreaksWithoutXcodebuild =
      resolvedPlatform.isApplePlatform
      && resolvedPlatform != .macOS
    if forceUsingXcodebuild
      || platformBreaksWithoutXcodebuild
    {
      forceUsingXcodebuild = true
    }

    // Allows the '--no-xcodebuild' flag to be passed in, to override whether
    // or not the swiftpm-based build system is used, even for embedded apple
    // platforms (ex. visionOS, iOS, tvOS, watchOS).
    return command.arguments.noXcodebuild ? false : forceUsingXcodebuild
  }
}
