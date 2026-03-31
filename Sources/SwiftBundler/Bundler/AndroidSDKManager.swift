import Foundation
import Version
import ErrorKit

enum AndroidSDKManager {
  static let buildToolsRelativePath = "build-tools"

  /// Locates the user's installed Android SDK.
  ///
  /// Checks for the presence of the `ANDROID_HOME` environment variable first,
  /// and otherwise searches standard platform-specific locations for the SDK.
  static func locateAndroidSDK() throws(Error) -> URL {
    let environmentVariable = "ANDROID_HOME"
    if let androidHome = ProcessInfo.processInfo.environment[environmentVariable] {
      let androidHome = URL(fileURLWithPath: androidHome)
      guard androidHome.exists(withType: .directory) else {
        throw Error(.androidHomeDoesNotExist(
          environmentVariable: environmentVariable,
          value: androidHome
        ))
      }
      return androidHome
    }

    // Source: https://stackoverflow.com/a/51585165
    let guesses: [URL]
    #if os(macOS)
      let libraryDirectories = FileManager.default.urls(
        for: .libraryDirectory,
        in: .userDomainMask
      )
      guesses = libraryDirectories.map { $0 / "Android/sdk" }
    #elseif os(Linux)
      guesses = [
        FileManager.default.homeDirectoryForCurrentUser / "Android/Sdk"
      ]
    #elseif os(Windows)
      // The applicationSupportDirectory for user domain mask is %LOCALAPPDATA%.
      // Source: https://github.com/swiftlang/swift-foundation/blob/a49715d6f1c2b866b91ea06468e58ee5f8ca41dd/Sources/FoundationEssentials/FileManager/SearchPaths/FileManager%2BWindowsSearchPaths.swift#L45-L46
      let localAppDataDirectories = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      )
      guesses = localAppDataDirectories.map { $0 / "Android/sdk" }
    #else
      #error("Default Android SDK location unknown for target platform")
    #endif

    for guess in guesses {
      if guess.exists(withType: .directory) {
        return guess
      }
    }

    throw Error(.failedToLocateAndroidSDK(
      environmentVariable: environmentVariable,
      guesses: guesses
    ))
  }

  /// Enumerates the build tool versions available in the given sdk.
  static func enumerateBuildToolVersions(availableIn sdk: URL) throws(Error) -> [Version] {
    let buildTools = sdk / "build-tools"
    let contents = try Error.catch(withMessage: .sdkMissingBuildTools(sdk: sdk)) {
      try FileManager.default.contentsOfDirectory(at: buildTools)
    }

    var versions: [Version] = []
    for directory in contents where directory.exists(withType: .directory) {
      guard let version = Version(tolerant: directory.lastPathComponent) else {
        log.warning("Failed to parse build tools version of tools at '\(directory.path)'")
        continue
      }
      versions.append(version)
    }

    return versions
  }

  /// Gets the default SDK version to use for compilation (i.e. the latest SDK version).
  static func getDefaultCompilationSDKVersion(forSDK sdk: URL) throws(Error) -> Version {
    let buildToolVersions = try enumerateBuildToolVersions(availableIn: sdk)
    // Take the highest version
    guard let version = buildToolVersions.sorted().last else {
      throw Error(.noBuildToolsFound(sdk))
    }
    return version
  }

  static func ndkDirectory(forSDK sdk: URL) -> URL {
    sdk / "ndk"
  }

  /// Enumerates all available NDK versions in the given SDK.
  static func enumerateNDKVersions(
    availableIn sdk: URL
  ) throws(Error) -> [(location: URL, version: Version)] {
    let ndkDirectory = ndkDirectory(forSDK: sdk)
    guard ndkDirectory.exists() else {
      return []
    }

    let contents = try Error.catch {
      try FileManager.default.contentsOfDirectory(at: ndkDirectory)
    }

    var versions: [(URL, Version)] = []
    for directory in contents where directory.exists(withType: .directory) {
      do {
        let version = try getVersion(ofNDKAt: directory)
        versions.append((directory, version))
      } catch {
        // If someone places a malformed NDK in their SDK's ndk directory
        // then we shouldn't let that break the rest of our NDK discovery,
        // so we just warn instead of propagating the error.
        log.warning("\(ErrorKit.userFriendlyMessage(for: error))")
      }
    }

    let sdks = try Error.catch {
      try SwiftSDKManager.enumerateInstalledSwiftSDKs()
    }
    for sdk in sdks {
      do {
        guard
          sdk.triple.contains("-unknown-linux-android"),
          let ndk = try SwiftSDKManager.getLinkedNDK(fromAndroidSDK: sdk)
        else {
          continue
        }

        let version = try getVersion(ofNDKAt: ndk)
        versions.append((ndk, version))
        log.debug("Found NDK at '\(ndk.path)' via SDK at '\(sdk.root.path)'")
      } catch {
        log.warning("\(ErrorKit.userFriendlyMessage(for: error))")
      }
    }

    // If a Swift Android SDK is linked to an NDK that lives inside the user's
    // Android SDK then we may discover the same NDK twice. Users may also just
    // have multiple installations of the exact same NDK version in some cases.
    var uniqueVersions: [(URL, Version)] = []
    var seen: Set<Version> = []
    for (url, version) in versions {
      if seen.insert(version).inserted {
        uniqueVersions.append((url, version))
      }
    }

    return uniqueVersions
  }

  /// Parses the content of a `*.properties` file (such as the
  /// source.properties file at the root of each NDK). Performs very
  /// relaxed parsing and only understands the features that we
  /// need to parse for our purposes (getting the versions of NDKs).
  private static func parsePropertiesFileContent(
    _ content: String) throws(Error) -> [String: String] {
    let lines = content.split(separator: "\n")
    var values: [String: String] = [:]
    for line in lines {
      let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty else {
        continue
      }

      let parts = line.split(separator: "=", maxSplits: 1)
      guard parts.count == 2 else {
        // Properties files can contain comments and other various constructs
        // besides key value pairs. Its best for us to ignore things we don't
        // understand here. c.f. https://en.wikipedia.org/wiki/.properties
        log.debug("Skipping property line with content '\(line)'")
        continue
      }

      let key = parts[0].trimmingCharacters(in: .whitespaces)
      let value = parts[1].trimmingCharacters(in: .whitespaces)
      values[String(key)] = String(value)
    }

    return values
  }

  /// Gets the version of the NDK at the given URL.
  static func getVersion(ofNDKAt ndk: URL) throws(Error) -> Version {
    let propertiesFile = ndk / "source.properties"
    guard propertiesFile.exists() else {
      throw Error(.ndkMissingSourceProperties(ndk))
    }

    let content = try Error.catch {
      try String(contentsOf: propertiesFile)
    }

    let values = try parsePropertiesFileContent(content)
    guard let version = values["Pkg.Revision"] else {
      throw Error(.ndkMissingRevision(ndk, values))
    }

    guard let parsedVersion = Version(tolerant: version) else {
      throw Error(.invalidNDKRevision(ndk, version))
    }

    return parsedVersion
  }

  /// Gets the path of the latest NDK version available in the given SDK.
  static func getLatestNDK(availableIn sdk: URL) throws(Error) -> URL {
    let ndkVersions = try enumerateNDKVersions(availableIn: sdk)
    let ndkDirectory = ndkDirectory(forSDK: sdk)
    guard
      let ndkVersion = ndkVersions.sorted(by: { $0.version <= $1.version }).last
    else {
      throw Error(.ndkNotInstalled(ndkDirectory))
    }

    return ndkVersion.location
  }

  static func llvmPrebuiltDirectory(
    forNDK ndk: URL,
    hostPlatform: HostPlatform,
    hostArchitecture: BuildArchitecture
  ) throws(Error) -> URL {
    // Ref: https://github.com/android/ndk/issues/1752
    guard hostPlatform == .macOS || hostArchitecture == .x86_64 else {
      throw Error(.ndkLLVMPrebuiltsOnlyDistributedForX86_64(hostPlatform, hostArchitecture))
    }

    let platformName = switch hostPlatform {
      case .linux: "linux"
      case .macOS: "darwin"
      case .windows: "windows"
    }

    let prebuiltDirectory = ndk / "toolchains/llvm/prebuilt/\(platformName)-x86_64"
    guard prebuiltDirectory.exists(withType: .directory) else {
      throw Error(.ndkMissingNDKPrebuilts(prebuiltDirectory))
    }

    return prebuiltDirectory
  }

  static func locateReadelfTool(
    inNDK ndk: URL,
    hostPlatform: HostPlatform,
    hostArchitecture: BuildArchitecture
  ) throws(Error) -> URL {
    let prebuiltDirectory = try llvmPrebuiltDirectory(
      forNDK: ndk,
      hostPlatform: .hostPlatform,
      hostArchitecture: .host
    )
    let readelfTool = prebuiltDirectory / "bin/llvm-readelf"
    guard readelfTool.exists() else {
      throw Error(.ndkMissingReadelfTool(readelfTool))
    }
    return readelfTool
  }
}
