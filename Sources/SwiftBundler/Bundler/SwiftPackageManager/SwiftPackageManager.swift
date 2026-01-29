import ArgumentParser
import Foundation
import Parsing
import Version
import Yams

/// A utility for interacting with the Swift package manager and performing some other package
/// related operations.
enum SwiftPackageManager {
  /// The context for a build.
  struct BuildContext {
    /// Generic build context properties shared between most build systems.
    var genericContext: GenericBuildContext
    /// An alternative Swift toolchain to use.
    var toolchain: URL?
    /// Controls whether the hot reloading environment variables are added to
    /// the build command or not.
    var hotReloadingEnabled: Bool = false
    /// Specifically controls whether whether the product gets built as a console
    /// or a GUI exe on Windows. Doesn't affect other platforms. On Windows, exes
    /// are either console executables (which open a command prompt window when
    /// double clicked) or GUI executables (which open normally when double clicked
    /// but can't really be run from command prompt because they instantly detach).
    var isGUIExecutable: Bool
    /// The compiled metadata. Either an object file or a static library depending on platform.
    var compiledMetadata: MetadataInserter.CompiledMetadata?
  }

  /// Creates a new package using the given directory as the package's root directory.
  /// - Parameters:
  ///   - directory: The package's root directory (will be created if it doesn't exist).
  ///   - name: The name for the package.
  ///   - toolchain: An alternative Swift toolchain to use.
  /// - Returns: If an error occurs, a failure is returned.
  static func createPackage(
    in directory: URL,
    name: String,
    toolchain: URL?
  ) async throws(Error) {
    // Create the package directory if it doesn't exist
    if !directory.exists(withType: .directory) {
      try FileManager.default.createDirectory(
        at: directory,
        errorMessage: ErrorMessage.failedToCreatePackageDirectory
      )
    }

    // Run the init command
    let arguments = [
      "package", "init",
      "--type=executable",
      "--name=\(name)",
    ]

    let process = Process.create(
      swiftPath(toolchain: toolchain),
      arguments: arguments,
      directory: directory
    )
    process.setOutputPipe(Pipe())

    try await Error.catch {
      try await process.runAndWait()
    }
  }

  /// Gets the path of the Swift executable for the given toolchain (if any).
  /// Returns the literal string `"swift"` when no toolchain is specified, so
  /// that Process can perform its usual executable path resolution.
  private static func swiftPath(toolchain: URL?) -> String {
    toolchain.map { $0 / "usr/bin/swift" }.map(\.path) ?? "swift"
  }

  /// Builds the specified product of a Swift package.
  /// - Parameters:
  ///   - product: The product to build.
  ///   - buildContext: The context to build in.
  /// - Returns: If an error occurs, returns a failure.
  static func build(
    product: String,
    buildContext: BuildContext
  ) async throws(Error) {
    let arguments = try await createBuildArguments(
      product: product,
      buildContext: buildContext
    )

    let process = Process.create(
      swiftPath(toolchain: buildContext.toolchain),
      arguments: arguments,
      directory: buildContext.genericContext.projectDirectory,
      runSilentlyWhenNotVerbose: false
    )

    if buildContext.hotReloadingEnabled {
      process.addEnvironmentVariables([
        "SWIFT_BUNDLER_HOT_RELOADING": "1"
      ])
    }

    try await Error.catch {
      try await process.runAndWait()
    }
  }

  /// Reads a build plan yaml file.
  private static func readBuildPlan(_ file: URL) throws(Error) -> BuildPlan {
    let buildPlanString: String
    do {
      buildPlanString = try String(contentsOf: file)
    } catch {
      throw Error(.failedToReadBuildPlan(path: file), cause: error)
    }

    return try Error.catch(withMessage: .failedToDecodeBuildPlan) {
      try YAMLDecoder().decode(BuildPlan.self, from: buildPlanString)
    }
  }

  /// Builds the specified executable product of a Swift package as a dynamic library.
  /// Used in hot reloading, should not be relied upon for producing production builds.
  /// - Parameters:
  ///   - product: The product to build.
  ///   - buildContext: The context to build in.
  static func buildExecutableAsDylib(
    product: String,
    buildContext: BuildContext
  ) async throws(Error) -> URL {
    #if os(macOS)
      let productsDirectory = try await SwiftPackageManager.getProductsDirectory(buildContext)
      let dylibExtension: String
      switch buildContext.genericContext.platform {
        case .macOS:
          dylibExtension = "dylib"
        case .android:
          dylibExtension = "so"
        case let platform:
          throw Error(.cannotCompileExecutableAsDylibForPlatform(platform))
      }
      let dylibFile = productsDirectory / "lib\(product).\(dylibExtension)"

      try await build(
        product: product,
        buildContext: buildContext
      )

      let buildPlanFile = buildContext.genericContext.scratchDirectory
        / "\(buildContext.genericContext.configuration).yaml"
      let buildPlan = try readBuildPlan(buildPlanFile)

      let triple: String
      switch buildContext.genericContext.platform {
        case .macOS:
          let targetInfo = try await getHostTargetInfo(toolchain: buildContext.toolchain)
          triple = targetInfo.target.triple
        case .android:
          triple = try Error.catch {
            try buildContext.genericContext.platform.targetTriple(
              // TODO: Clean this up so that we don't have to assume that there's exactly 1
              //   architecture specified for Android builds (make it more verifiable).
              withArchitecture: buildContext.genericContext.architectures[0],
              andPlatformVersion: buildContext.genericContext.platformVersion
            ).description
          }
        case let platform:
          throw Error(.cannotCompileExecutableAsDylibForPlatform(platform))
      }

      // Swift versions before 6.0 or so named commands differently in the build plan.
      // We check for the newer format (with triple) then the older format (no triple).
      let configuration = buildContext.genericContext.configuration
      let commandName = "C.\(product)-\(triple)-\(configuration).exe"
      let oldCommandName = "C.\(product)-\(configuration).exe"
      guard
        let linkCommand = buildPlan.commands[commandName] ?? buildPlan.commands[oldCommandName],
        linkCommand.tool == "shell",
        let commandExecutable = linkCommand.arguments?.first,
        let arguments = linkCommand.arguments?.dropFirst()
      else {
        let message = ErrorMessage.failedToComputeLinkingCommand(
          details: "Couldn't find valid command for \(commandName)"
        )
        throw Error(message)
      }

      var modifiedArguments = Array(arguments)
      guard
        let index = modifiedArguments.firstIndex(of: "-o"),
        index < modifiedArguments.count - 1
      else {
        let details = "Couldn't find '-o' argument to replace"
        throw Error(.failedToComputeLinkingCommand(details: details))
      }

      modifiedArguments.remove(at: index)
      modifiedArguments.remove(at: index)
      modifiedArguments.append(contentsOf: ["-o", dylibFile.path])

      switch buildContext.genericContext.platform {
        case .macOS:
          modifiedArguments.append(contentsOf: [
            "-Xcc",
            "-dynamiclib",
          ])
        case .android:
          modifiedArguments.removeAll { $0 == "-emit-executable" }
          modifiedArguments.append("-emit-library")
          // If we don't set an soname, then the library gets linked at its
          // absolute path on the host machine when used with CMake in gradle
          // projects. That leads to a runtime linker error when running the
          // built app on an Android device, because the absolute path of the
          // library on the host machine doesn't exist on the Android device.
          modifiedArguments.append(contentsOf: [
            "-Xlinker", "-soname", "-Xlinker", dylibFile.lastPathComponent
          ])
        case let platform:
          throw Error(.cannotCompileExecutableAsDylibForPlatform(platform))
      }

      do {
        let process = Process.create(
          commandExecutable,
          arguments: modifiedArguments,
          directory: buildContext.genericContext.projectDirectory,
          runSilentlyWhenNotVerbose: false
        )
        try await process.runAndWait()
      } catch {
        throw Error(.failedToRunModifiedLinkingCommand)
      }

      return dylibFile
    #else
      fatalError("buildExecutableAsDylib not implemented for current platform")
      #warning("buildExecutableAsDylib not implemented for current platform")
    #endif
  }

  /// Creates the arguments for the Swift build command.
  /// - Parameters:
  ///   - product: The product to build.
  ///   - buildContext: The context to build in.
  /// - Returns: The build arguments.
  static func createBuildArguments(
    product: String?,
    buildContext: BuildContext
  ) async throws(Error) -> [String] {
    let platform = buildContext.genericContext.platform
    var platformArguments: [String]
    switch platform {
      case .windows:
        let debugArguments: [String]
        let guiArguments: [String]

        if buildContext.genericContext.configuration == .debug {
          debugArguments = [
            "-Xswiftc", "-g",
            "-Xswiftc", "-debug-info-format=codeview",
            "-Xlinker", "-debug",
          ]
        } else {
          debugArguments = []
        }

        if buildContext.isGUIExecutable {
          let frontendArguments = ["-entry-point-function-name", "wWinMain"]
          let swiftcArguments = frontendArguments.flatMap { ["-Xfrontend", $0] }
          guiArguments = swiftcArguments.flatMap { ["-Xswiftc", $0] } +
            ["-Xlinker", "/SUBSYSTEM:WINDOWS"]
        } else {
          guiArguments = []
        }

        platformArguments = debugArguments + guiArguments
      case .macCatalyst, .iOS, .visionOS, .tvOS,
        .iOSSimulator, .visionOSSimulator, .tvOSSimulator:
        // Handle all non-Mac Apple platforms
        let sdkPath = try await getLatestSDKPath(for: platform)

        guard let platformVersion = buildContext.genericContext.platformVersion else {
          throw Error(.missingDarwinPlatformVersion(platform))
        }
        let hostArchitecture = BuildArchitecture.host

        let targetTriple = try Error.catch {
          try platform.targetTriple(
            withArchitecture: platform.usesHostArchitecture ? hostArchitecture : .arm64,
            andPlatformVersion: platformVersion
          )
        }

        platformArguments =
          [
            "-sdk", sdkPath,
            "-target", targetTriple.description,
          ].flatMap { ["-Xswiftc", $0] }
          + [
            "--target=\(targetTriple)",
            "-isysroot", sdkPath,
          ].flatMap { ["-Xcc", $0] }

        if platform == .macCatalyst {
          platformArguments += [
            "-I", "\(sdkPath)/../../usr/lib",
            "-Fsystem", "\(sdkPath)/System/iOSSupport/System/Library/Frameworks",
            "-F", "\(sdkPath)/../../Library/Frameworks",
          ].flatMap { ["-Xswiftc", $0] }
          + [
            "-isystem", "\(sdkPath)/System/iOSSupport/usr/include"
          ].flatMap { ["-Xcc", $0] }
        }
      case .android:
        guard buildContext.genericContext.architectures.count == 1 else {
          throw Error(.cannotBuildForMultipleAndroidArchitecturesAtOnce)
        }

        let targetTriple = try Error.catch {
          try platform.targetTriple(
            withArchitecture: buildContext.genericContext.architectures[0],
            andPlatformVersion: "28"
          )
        }

        let sdk = try Error.catch {
          try SwiftSDKManager.locateSDKMatching(
            hostPlatform: .hostPlatform,
            hostArchitecture: .host,
            targetTriple: targetTriple
          )
        }

        let silo = try Error.catch {
          try SwiftSDKManager.getPopulatedSDKSilo(forSDK: sdk)
        }

        log.debug("Using Swift SDK silo at '\(silo.path)'")

        let debugArguments = buildContext.genericContext.configuration == .debug
          ? ["-Xswiftc", "-g"]
          : []

        platformArguments = [
          "--swift-sdks-path", silo.path,
          "--swift-sdk", sdk.triple
        ] + debugArguments
      case .macOS, .linux:
        platformArguments = buildContext.genericContext.configuration == .debug
          ? ["-Xswiftc", "-g"]
          : []
    }

    let architectureArguments: [String]
    if platformArguments.contains("--triple") {
      architectureArguments = []
    } else {
      architectureArguments = buildContext.genericContext.architectures.flatMap { architecture in
          ["--arch", architecture.argument(for: buildContext.genericContext.platform)]
      }
    }

    let productArguments = product.map { ["--product", $0] } ?? []
    let scratchDirectoryArguments = [
      "--scratch-path", buildContext.genericContext.scratchDirectory.path,
    ]
    var arguments = [
      "build",
      "-c", buildContext.genericContext.configuration.rawValue,
    ]
    arguments += productArguments
    arguments += architectureArguments
    arguments += platformArguments
    arguments += scratchDirectoryArguments
    arguments += buildContext.genericContext.additionalArguments
    if let compiledMetadata = buildContext.compiledMetadata {
      arguments += MetadataInserter.additionalSwiftPackageManagerArguments(
        toInsert: compiledMetadata
      )
    }

    return arguments
  }

  /// Gets the path to the latest SDK for a given platform.
  /// - Parameter platform: The platform to get the SDK path for.
  /// - Returns: The SDK's path.
  static func getLatestSDKPath(for platform: Platform) async throws(Error) -> String {
    do {
      let output = try await Process.create(
        "/usr/bin/xcrun",
        arguments: [
          "--sdk", platform.sdkName,
          "--show-sdk-path",
        ]
      ).getOutput()
      return output.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      throw Error(.failedToGetLatestSDKPath(platform), cause: error)
    }
  }

  // The first two examples are for release versions of Swift (the first on
  // macOS, the second on Linux). The next two examples are for snapshot
  // versions of Swift (the first on macOS, the second on Linux).
  //
  // Sample: "swift-driver version: 1.45.2 Apple Swift version 5.6 (swiftlang-5.6.0.323.62 clang-1316.0.20.8)"
  //     OR: "swift-driver version: 1.45.2 Swift version 5.6 (swiftlang-5.6.0.323.62 clang-1316.0.20.8)"
  //     OR: "Apple Swift version 5.9-dev (LLVM 464b04eb9b157e3, Swift 7203d52cb1e074d)"
  //     OR: "Swift version 5.9-dev (LLVM 464b04eb9b157e3, Swift 7203d52cb1e074d)"
  private static let swiftVersionParser = OneOf {
    Parse {
      "swift-driver version"
      Prefix { $0 != "(" }
      "(swiftlang-"
      Parse({ Version(major: $0, minor: $1, patch: $2) }) {
        Int.parser(radix: 10)
        "."
        Int.parser(radix: 10)
        "."
        Int.parser(radix: 10)
      }
      Rest<Substring>()
    }.map { (_: Substring, version: Version, _: Substring) in
      version
    }

    Parse {
      Optionally {
        "Apple "
      }
      "Swift version "
      Parse({ Version(major: $0, minor: $1, patch: 0) }) {
        Int.parser(radix: 10)
        "."
        Int.parser(radix: 10)
      }
      Rest<Substring>()
    }.map { (_: Void?, version: Version, _: Substring) in
      version
    }
  }

  /// Gets the version of the current Swift installation.
  /// - Parameter toolchain: An alternative Swift toolchain to use.
  /// - Returns: The swift version.
  static func getSwiftVersion(toolchain: URL?) async throws(Error) -> Version {
    let output = try await Error.catch(withMessage: .failedToGetSwiftVersion) {
      try await Process.create(
        swiftPath(toolchain: toolchain),
        arguments: ["--version"]
      ).getOutput()
    }

    do {
      return try swiftVersionParser.parse(output)
    } catch {
      throw Error(.invalidSwiftVersionOutput(output), cause: error)
    }
  }

  /// Gets the default products directory for builds occuring within the given context.
  /// - Parameters:
  ///   - buildContext: The context the build is occuring within.
  /// - Returns: The default products directory.
  static func getProductsDirectory(_ buildContext: BuildContext) async throws(Error) -> URL {
    let arguments = try await createBuildArguments(
      product: nil,
      buildContext: buildContext
    )

    let process = Process.create(
      swiftPath(toolchain: buildContext.toolchain),
      arguments: arguments + ["--show-bin-path"],
      directory: buildContext.genericContext.projectDirectory
    )

    do {
      let output = try await process.getOutput()
      return URL(fileURLWithPath: output.trimmingCharacters(in: .newlines))
    } catch {
      throw Error(
        .failedToGetProductsDirectory,
        cause: error
      )
    }
  }

  /// Loads a root package manifest from a package's root directory.
  /// - Parameters:
  ///   - packageDirectory: The package's root directory.
  ///   - toolchain: An alternative Swift toolchain to use.
  /// - Returns: The loaded manifest.
  static func loadPackageManifest(
    from packageDirectory: URL,
    toolchain: URL?
  ) async throws(Error) -> PackageManifest {
    let process = Process.create(
      swiftPath(toolchain: toolchain),
      arguments: ["package", "describe", "--type", "json"],
      directory: packageDirectory
    )

    let output = try await Error.catch {
      try await process.getOutput(excludeStdError: true)
    }

    // Drop lines before the start of the JSON. SwiftPM sometimes prints
    // warnings to stdout before printing the JSON. Handles \r\n line endings
    // correctly.
    let lines = output.split(separator: "\n")
    let jsonLines = lines.drop { line in
      !line.hasPrefix("{")
    }
    let json = jsonLines.joined(separator: "\n")

    let jsonData = Data(json.utf8)
    do {
      return try JSONDecoder().decode(PackageManifest.self, from: jsonData)
    } catch {
      throw Error(.failedToParsePackageManifestOutput(json: output), cause: error)
    }
  }

  /// Gets build target info about the host machine.
  /// - Parameter toolchain: An alternative Swift toolchain to use.
  static func getHostTargetInfo(toolchain: URL?) async throws(Error) -> SwiftTargetInfo {
    // TODO: This could be a nice easy one to unit test
    let process = Process.create(
      swiftPath(toolchain: toolchain),
      arguments: ["-print-target-info"]
    )

    let output = try await Error.catch {
      try await process.getOutput()
    }

    let data = Data(output.utf8)
    do {
      return try JSONDecoder().decode(SwiftTargetInfo.self, from: data)
    } catch {
      throw Error(.failedToParseTargetInfo(json: output), cause: error)
    }
  }

  /// Gets the Swift tools version.
  /// - Parameter toolchain: An alternative Swift toolchain version to use.
  static func getToolsVersion(
    _ packageDirectory: URL,
    toolchain: URL?
  ) async throws(Error) -> Version {
    let version = try await Error.catch(withMessage: .failedToGetToolsVersion) {
      try await Process.create(
        swiftPath(toolchain: toolchain),
        arguments: ["package", "tools-version"],
        directory: packageDirectory
      ).getOutput()
    }

    guard
      let parsedVersion = Version(
        version.trimmingCharacters(in: .whitespacesAndNewlines)
      )
    else {
      throw Error(.invalidToolsVersion(version))
    }
    return parsedVersion
  }

  /// Returns the standard locations of SwiftPM's config/data directory. Only
  /// returns those that actually exist.
  static func standardSwiftPMDirectories() -> [URL] {
    var directories = [
      FileManager.default.homeDirectoryForCurrentUser / ".swiftpm"
    ]
    #if os(macOS)
      directories += FileManager.default.urls(
        for: .libraryDirectory,
        in: .userDomainMask
      ).map { $0 / "org.swift.swiftpm" }
    #endif
    directories = directories.map { directory in
      directory.actuallyResolvingSymlinksInPath()
    }.uniqued().filter { directory in
      directory.exists()
    }
    return directories
  }

  /// Parses the metadata of the provided artifactbundle. Metadata is read from
  /// the bundle's info.json file.
  static func parseArtifactBundle(_ bundle: URL) throws(Error) -> ArtifactBundleMetadata {
    let infoFile = bundle / "info.json"
    return try Error.catch(withMessage: .failedToReadArtifactBundleInfoJSON(infoFile)) {
      let data = try Data(contentsOf: infoFile)
      return try JSONDecoder().decode(ArtifactBundleMetadata.self, from: data)
    }
  }
}
