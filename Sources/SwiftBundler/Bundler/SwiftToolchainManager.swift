import Foundation

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
