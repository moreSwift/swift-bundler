import Foundation
import Parsing

/// A manager for Swift toolchains.
enum SwiftToolchainManager {
  /// Locates as many Swift toolchains on the user's system as we can find.
  static func locateSwiftToolchains() async throws(Error) -> [SwiftToolchain] {
    let searchDirectories = try await locateSwiftToolchainSearchDirectories()
    log.debug("Toolchain search directories: \(searchDirectories)")

    // Locate toolchain candidates in each search directory (without validating
    // that they are usable toolchains).
    var candidateToolchains: [(root: URL, isCommandLineTools: Bool)] = []
    for searchDirectory in searchDirectories {
      do {
        let contents = try FileManager.default.contentsOfDirectory(at: searchDirectory)
        let directories = contents.filter { $0.exists(withType: .directory) }
        for directory in directories {
          let resolved = directory.actuallyResolvingSymlinksInPath()
          if !candidateToolchains.map(\.root).contains(resolved) {
            candidateToolchains.append((resolved, false))
          }
        }
      } catch {
        log.warning(
          """
          Failed to enumerate toolchains in '\(searchDirectory.path)': \
          \(error.localizedDescription)
          """
        )
      }
    }

    // Add CommandLineTools as a candidate toolchain if it's installed
    if HostPlatform.hostPlatform == .macOS {
      do {
        let libraryDirectory = try FileManager.default.url(
          for: .libraryDirectory,
          in: .localDomainMask,
          appropriateFor: nil,
          create: false
        )
        let commandLineTools = libraryDirectory / "/Developer/CommandLineTools"
        if commandLineTools.exists(withType: .directory) {
          candidateToolchains.append((commandLineTools, true))
        }
      } catch {
        log.warning(
          "Failed to check for CommandLineTools installation: \(error.localizedDescription)"
        )
      }
    }

    // Attempt to load each of the toolchain candidates that we've found
    var toolchains: [SwiftToolchain] = []
    for candidateToolchain in candidateToolchains {
      log.debug("Loading Swift toolchain at '\(candidateToolchain.root.path)'")
      do {
        let toolchain = try await loadSwiftToolchain(
          candidateToolchain.root,
          isCommandLineTools: candidateToolchain.isCommandLineTools
        )
        toolchains.append(toolchain)
      } catch {
        log.warning(
          """
          Failed to load toolchain at '\(candidateToolchain.root.path)': \
          \(error.localizedDescription)
          """
        )
      }
    }

    return toolchains
  }

  /// Locate directories that could contain Swift toolchains.
  private static func locateSwiftToolchainSearchDirectories()
    async throws(Error) -> [URL]
  {
    var searchDirectories: [URL] = []
    if HostPlatform.hostPlatform == .macOS {
      // Locate system-wide and user toolchain directories
      let urls = FileManager.default.urls(
        for: .libraryDirectory,
        in: .allDomainsMask
      )
      searchDirectories.append(contentsOf: urls.map { $0 / "Developer/Toolchains" })

      // Add Xcode toolchains directory if we can find it
      do {
        let directory = try await Error.catch {
          try await XcodeSelect.locateXcodeToolchainsDirectory()
        }
        if let directory {
          searchDirectories.append(directory)
        }
      } catch {
        log.debug(
          """
          Failed to locate Xcode installation, may not be installed: \
          \(error.localizedDescription)
          """
        )
      }
    }

    // Respect custom Swiftly toolchain installation directory
    if let customSwiftlyToolchainsDirectory =
          ProcessInfo.processInfo.environment["SWIFTLY_TOOLCHAINS_DIR"] {
      let toolchainsDirectory = URL(fileURLWithPath: customSwiftlyToolchainsDirectory)
      searchDirectories.append(toolchainsDirectory)
    }

    // If on Linux, add the default Swiftly toolchains directory. We don't do
    // this on macOS because the default Swiftly toolchain directory on macOS
    // is `~/Library/Developer/Toolchains` which we already cover. We do this
    // even if SWIFTLY_TOOLCHAINS_DIR is set because we want to find as many
    // toolchains as possible (not just the ones that Swiftly is currently
    // configured to use).
    if HostPlatform.hostPlatform == .linux {
      let home = FileManager.default.homeDirectoryForCurrentUser
      let toolchainsDirectory = home / ".local/share/swiftly/toolchains"
      searchDirectories.append(toolchainsDirectory)
    }

    // Remove non-existent directories, resolve symlinks, remove duplicates
    searchDirectories = searchDirectories
      .filter { $0.exists(withType: .directory) }
      .map { $0.actuallyResolvingSymlinksInPath() }
      .uniqued()

    return searchDirectories
  }

  /// Loads a standalone Swift toolchain, Xcode toolchain, or CommandLineTools
  /// installation as a Swift toolchain that Swift Bundler can use.
  ///
  /// - Parameter isCommandLineTools: We can't automatically detect this so
  ///   whether we treat the toolchain as CommandLineTools or not depends on
  ///   how the toolchain was discovered (i.e. it is up to the callee to tell us).
  static func loadSwiftToolchain(
    _ toolchain: URL,
    isCommandLineTools: Bool
  ) async throws(Error) -> SwiftToolchain {
    let versionString = try await Error.catch {
      try await SwiftPackageManager.getHostTargetInfo(
        toolchain: toolchain
      ).compilerVersion
    }

    // Ensure that the toolchain has a swift executable (that we can find)
    let swiftPath = SwiftToolchain.swiftExecutable(
      forToolchainWithRoot: toolchain
    )
    guard swiftPath.exists() else {
      throw Error(.toolchainMissingSwiftExecutable(
        toolchain: toolchain,
        swiftExecutable: swiftPath
      ))
    }

    // Detect the kind of toolchain that we're working with, and compute the
    // toolchain's display name
    let displayName: String
    let kind: SwiftToolchain.Kind
    let infoPlist = toolchain / "Info.plist"
    let xcodeToolchainInfoPlist = toolchain / "ToolchainInfo.plist"
    if isCommandLineTools {
      displayName = "\(versionString) (CommandLineTools)"
      kind = .xcodeCommandLineTools
    } else if infoPlist.exists() {
      let manifest = try Error.catch(
        withMessage: .failedToLoadToolchainInfoPlist(infoPlist)
      ) {
        let contents = try Data(contentsOf: infoPlist)
        return try PropertyListDecoder().decode(
          ToolchainInfoPlist.self,
          from: contents
        )
      }

      displayName = manifest.displayName
      kind = .standalone
    } else if xcodeToolchainInfoPlist.exists() {
      displayName = "\(versionString) (Xcode)"
      kind = .xcodeToolchain
    } else {
      displayName = "\(versionString) (unknown)"
      kind = .unknown

      log.warning(
        """
        Discovered toolchain at '\(toolchain.path)' which doesn't match any \
        toolchain structure known to Swift Bundler, but does have a Swift \
        executable. Loading and treating as an unknown toolchain kind.
        """
      )
    } 

    return SwiftToolchain(
      root: toolchain,
      displayName: displayName,
      compilerVersionString: versionString,
      kind: kind
    )
  }

  /// Locates a Swift toolchain compatible with the given Swift Android SDK.
  ///
  /// Logs a warning if multiple compatible toolchains are found.
  static func locateSwiftToolchain(
    compatibleWithAndroidSDK androidSDK: SwiftSDK
  ) async throws(Error) -> SwiftToolchain {
    // TODO(stackotter): Update if we implement proper triple parsing
    guard androidSDK.triple.contains("-unknown-linux-android") else {
      throw Error(.cannotDoToolchainMatchingForNonAndroidSDKs(androidSDK))
    }

    let compilerVersionString = try Error.catch {
      try SwiftSDKManager.getCompilerVersionString(fromAndroidSDK: androidSDK)
    }
    let compilerVersion = try parseSwiftCompilerVersionString(compilerVersionString)

    let toolchains = try await Error.catch {
      try await locateSwiftToolchains()
    }

    var parsedToolchains: [(toolchain: SwiftToolchain, version: SwiftCompilerVersion)] = []
    for toolchain in toolchains {
      do {
        let toolchainCompilerVersion = try parseSwiftCompilerVersionString(
          toolchain.compilerVersionString
        )
        parsedToolchains.append((toolchain, toolchainCompilerVersion))
      } catch {
        log.warning(
          """
          Failed to parse toolchain compiler version \
          '\(toolchain.compilerVersionString)' of toolchain at \
          '\(toolchain.root.path)'; skipping
          """
        )
        continue
      }
    }

    func computeKey(
      toolchainVersion: SwiftCompilerVersion,
      sdkVersion: SwiftCompilerVersion,
      tieBreaker: SwiftToolchain?
    ) -> (Int, Int, String) {
      (
        (toolchainVersion.exactVersion == sdkVersion.exactVersion) ? 1 : 0,
        (toolchainVersion.shortVersion == sdkVersion.shortVersion) ? 1 : 0,
        // Use toolchain paths to provide stable ordering in the case of ties
        tieBreaker?.root.path ?? ""
      )
    }

    let sortedToolchains = parsedToolchains.filter { toolchain in
      toolchain.version.exactVersion == compilerVersion.exactVersion
      || toolchain.version.shortVersion == compilerVersion.shortVersion
    }.sorted { first, second in
      computeKey(
        toolchainVersion: first.version,
        sdkVersion: compilerVersion,
        tieBreaker: first.toolchain
      ) <= computeKey(
        toolchainVersion: second.version,
        sdkVersion: compilerVersion,
        tieBreaker: second.toolchain
      )
    }

    log.debug(
      """
      Sorted toolchain candidates (in order of increasing relevance): \
      \(sortedToolchains)
      """
    )

    guard let toolchain = sortedToolchains.last else {
      throw Error(.failedToFindToolchainMatchingAndroidSDK(androidSDK))
    }

    let bestKey = computeKey(
      toolchainVersion: toolchain.version,
      sdkVersion: compilerVersion,
      tieBreaker: nil
    )
    let equalMatches = sortedToolchains.filter { otherToolchain in
      computeKey(
        toolchainVersion: otherToolchain.version,
        sdkVersion: compilerVersion,
        tieBreaker: nil
      ) == bestKey
    }

    if equalMatches.count > 1 {
      log.warning(
        """
        Found multiple Swift toolchains compatible with given Android SDK \
        ('\(androidSDK.generallyUniqueIdentifier)'). Choosing one at \
        '\(toolchain.toolchain.root.path)'. Use '-v' to see all compatible \
        toolchains
        """
      )
      log.debug("Compatible toolchains: \(equalMatches)")
    }

    return toolchain.toolchain
  }

  /// A parsed Swift compiler version (from `swift -version` or
  /// `swift -print-target-info`)
  struct SwiftCompilerVersion: Hashable, Sendable {
    // The full un-parsed version string.
    var fullVersionString: String
    // The compiler's variant (e.g. Apple, or SwiftWasm).
    var variant: String?
    // The short version (e.g. 6.0.3).
    var shortVersion: String
    // The exact version (e.g. 6.0.3.1.10, or a commit hash).
    var exactVersion: String
  }

  /// Parses a Swift compiler version string (from `swift -version` or
  /// `swift -print-target-info`).
  static func parseSwiftCompilerVersionString(
    _ versionString: String
  ) throws(Error) -> SwiftCompilerVersion {
    // Example version strings:
    //   Apple Swift version 6.1.2 (swiftlang-6.1.2.1.2 clang-1700.0.13.5)
    //   SwiftWasm Swift version 5.9.2 (swift-5.9.2-RELEASE)
    //   Apple Swift version 6.0.3 (swiftlang-6.0.3.1.10 clang-1600.0.30.1)
    //   Apple Swift version 6.3-dev (LLVM 732b15bc343f6d4, Swift aec3d15e6fbe41c)
    //   Swift version 6.3-dev effective-5.10 (Swift aec3d15e6fbe41c)
    //   swift-driver version: 1.120.5 Apple Swift version 6.1.2 (swiftlang-6.1.2.1.2 clang-1700.0.13.5)
    let parser = Parse(input: Substring.self) {
      PrefixUpTo("Swift version ")
      "Swift version "
      PrefixUpTo(" ")

      PrefixThrough("(").map { _ in }
      PrefixUpTo(")")
      ")"
    }
    let (variantPart, shortVersion, exactVersionsSection) = try Error.catch {
      try parser.parse(versionString)
    }

    // There are two variants of the parenthesized exact version section; one
    // that's space separated, and one that's comma separated. We can't use
    // commas to detect the comma separated variant because the list sometimes
    // only has a single entry. And we can't just separate on spaces and trim
    // commas because the comma separated entries contain spaces within them.
    // We use the string 'Swift ' to detect the comma separated variant because
    // if it's not present we'd fail to extract the Swift version anyway.
    let exactSwiftVersion: String
    if exactVersionsSection.contains("Swift ") {
      let exactVersionParts = exactVersionsSection.components(separatedBy: ", ")
      let prefix = "Swift "
      guard let swiftPart = exactVersionParts.first(where: {
        $0.starts(with: prefix)
      }) else {
        throw Error(.failedToParseSwiftCompilerVersionString(
          versionString: versionString,
          message: """
            Expected to find version preceeded by '\(prefix)' within the \
            parenthesized section
            """
        ))
      }

      exactSwiftVersion = String(swiftPart.dropFirst(prefix.count))
    } else {
      let exactVersionParts = exactVersionsSection.split(separator: " ")
      let prefix1 = "swift-"
      let prefix2 = "swiftlang-"
      guard let swiftPart = exactVersionParts.first(where: {
        $0.starts(with: prefix1) || $0.starts(with: prefix2)
      }) else {
        throw Error(.failedToParseSwiftCompilerVersionString(
          versionString: versionString,
          message: """
            Expected to find version preceeded by '\(prefix1)' or '\(prefix2)' \
            within the parenthesized section
            """
        ))
      }

      if swiftPart.starts(with: prefix1) {
        exactSwiftVersion = String(swiftPart.dropFirst(prefix1.count))
      } else {
        exactSwiftVersion = String(swiftPart.dropFirst(prefix2.count))
      }
    }

    let variant: String?
    let trimmedVariantPart = variantPart
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedVariantPart.isEmpty {
      variant = nil
    } else {
      // Drop the swift-driver version if provided. It feels like a bug that
      // `swift -version` includes the driver version and Swift version on the
      // same line, but it does
      if trimmedVariantPart.starts(with: "swift-driver version: ") {
        let parts = trimmedVariantPart.split(separator: " ", maxSplits: 3)
        if parts.count == 4 {
          variant = String(parts[3])
        } else {
          variant = nil
        }
      } else {
        variant = trimmedVariantPart
      }
    }

    return SwiftCompilerVersion(
      fullVersionString: versionString,
      variant: variant,
      shortVersion: String(shortVersion),
      exactVersion: exactSwiftVersion
    )
  }

  /// A partial toolchain Info.plist (we don't decode all of the keys).
  struct ToolchainInfoPlist: Decodable {
    var aliases: [String]
    var bundleIdentifier: String
    var compatibilityVersion: Int
    var displayName: String
    var shortDisplayName: String
    var version: String

    enum CodingKeys: String, CodingKey {
      case aliases = "Aliases"
      case bundleIdentifier = "CFBundleIdentifier"
      case compatibilityVersion = "CompatibilityVersion"
      case displayName = "DisplayName"
      case shortDisplayName = "ShortDisplayName"
      case version = "Version"
    }
  }
}
