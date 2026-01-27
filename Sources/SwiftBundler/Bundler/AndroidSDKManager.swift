import Foundation
import Version

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
  static func enumerateNDKVersions(availableIn sdk: URL) throws(Error) -> [Version] {
    let ndkDirectory = ndkDirectory(forSDK: sdk)
    guard ndkDirectory.exists() else {
      return []
    }

    let contents = try Error.catch {
      try FileManager.default.contentsOfDirectory(at: ndkDirectory)
    }

    var versions: [Version] = []
    for directory in contents where directory.exists(withType: .directory) {
      guard let version = Version(tolerant: directory.lastPathComponent) else {
        log.warning("Failed to parse NDK version of NDK at '\(directory.path)'")
        continue
      }
      versions.append(version)
    }

    return versions
  }

  /// Gets the path of the latest NDK version available in the given SDK.
  static func getLatestNDK(availableIn sdk: URL) throws(Error) -> URL {
    let ndkVersions = try enumerateNDKVersions(availableIn: sdk)
    let ndkDirectory = ndkDirectory(forSDK: sdk)
    guard let ndkVersion = ndkVersions.sorted().last else {
      throw Error(.ndkNotInstalled(ndkDirectory))
    }

    return ndkDirectory / "\(ndkVersion)"
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
