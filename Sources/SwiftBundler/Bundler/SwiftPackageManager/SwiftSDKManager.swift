import Foundation

/// Locates and manages Swift SDKs. Does not involve itself with Xcode's platform
/// SDKs, only SwiftPM SDKs ([introduced in Swift 6.1](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0387-cross-compilation-destinations.md)).
enum SwiftSDKManager {
  /// Swift SDK schema versions supported by this SDK manager.
  static let supportedSchemaVersions = ["4.0"]

  /// Returns the standard locations of Swift's SDK installation directory. Only
  /// returns those that actually exist. Resolves symlinks and guarantees no duplicates.
  static func standardSDKDirectories() -> [URL] {
    SwiftPackageManager.standardSwiftPMDirectories().map { directory in
      directory / "swift-sdks"
    }.map { directory in
      directory.actuallyResolvingSymlinksInPath()
    }.uniqued().filter { directory in
      directory.exists()
    }
  }

  /// The host triple for the given platform and architecture as specified in
  /// Swift SDK supported host triple lists. The main difference to usual triples
  /// is that macOS gets represented as a `darwin` system instead of a `macosx` system.
  static func sdkHostTriple(
    forHostPlatform hostPlatform: HostPlatform,
    hostArchitecture: BuildArchitecture
  ) -> LLVMTargetTriple {
    let vendor: LLVMTargetTriple.Vendor = switch hostPlatform {
      case .macOS: .apple
      case .linux, .windows: .unknown
    }
    let system: LLVMTargetTriple.System = switch hostPlatform {
      case .macOS: .darwin
      case .linux: .linux
      case .windows: .windows
    }
    return LLVMTargetTriple(
      architecture: hostArchitecture,
      vendor: vendor,
      system: system
    )
  }

  /// Locates installed Swift SDKs matching the given host and target properties.
  static func locateSDKsMatching(
    hostPlatform: HostPlatform,
    hostArchitecture: BuildArchitecture,
    targetTriple: LLVMTargetTriple
  ) throws(Error) -> [SwiftSDK] {
    let sdks = try enumerateInstalledSwiftSDKs()
    return filterSDKs(
      sdks,
      hostPlatform: hostPlatform,
      hostArchitecture: hostArchitecture,
      targetTriple: targetTriple
    )
  }

  /// Locates a Swift SDK matching the given host and target properties. If multiple
  /// matching SDKs are found, a warning is printed and one of the multiple SDKs is
  /// returned. The SDK returned is unspecified, but should be consistent across runs.
  static func locateSDKMatching(
    hostPlatform: HostPlatform,
    hostArchitecture: BuildArchitecture,
    targetTriple: LLVMTargetTriple
  ) throws(Error) -> SwiftSDK {
    let sdks = try locateSDKsMatching(
      hostPlatform: hostPlatform,
      hostArchitecture: hostArchitecture,
      targetTriple: targetTriple
    ).sorted { first, second in
      first.generallyUniqueIdentifier <= second.generallyUniqueIdentifier
    }

    guard let sdk = sdks.first else {
      throw Error(.noSDKsMatchQuery(
        hostPlatform: hostPlatform,
        hostArchitecture: hostArchitecture,
        targetTriple: targetTriple
      ))
    }

    if sdks.count > 1 {
      log.warning(
        """
        Multiple SDKs match host platform '\(hostPlatform.platform.displayName)', \
        host architecture '\(hostArchitecture)', and target triple '\(targetTriple)':
        \(sdks.map(\.generallyUniqueIdentifier).map { "* \($0)" }.joined(separator: "\n"))
        Using \(sdk.generallyUniqueIdentifier)
        """
      )
    }

    return sdk
  }

  /// Filters a set of Swift SDKs to those matching the given host and target
  /// properties.
  static func filterSDKs(
    _ sdks: [SwiftSDK],
    hostPlatform: HostPlatform,
    hostArchitecture: BuildArchitecture,
    targetTriple: LLVMTargetTriple,
  ) -> [SwiftSDK] {
    let hostTriple = sdkHostTriple(
      forHostPlatform: hostPlatform,
      hostArchitecture: hostArchitecture
    )
    let targetTriple = targetTriple.description

    return sdks.filter { sdk in
      return sdk.supportsHostTriple(hostTriple)
        && sdk.triple == targetTriple
    }
  }

  /// Enumerates Swift SDKs installed at standard locations.
  static func enumerateInstalledSwiftSDKs() throws(Error) -> [SwiftSDK] {
    try standardSDKDirectories().flatMap { sdkDirectory throws(Error) in
      let artifactBundles = try Error.catch(withMessage: .failedToEnumerateSDKs(sdkDirectory)) {
        try FileManager.default.contentsOfDirectory(at: sdkDirectory)
      }

      var sdks: [SwiftSDK] = []
      for bundle in artifactBundles {
        do {
          let bundleSDKs = try enumerateSwiftSDKs(inArtifactBundle: bundle)
          sdks.append(contentsOf: bundleSDKs)
        } catch {
          log.warning("\(chainDescription(for: error, verbose: log.logLevel <= .debug))")
        }
      }

      return sdks
    }
  }

  /// Enumerates the SDKs declared by a given artifact bundle.
  static func enumerateSwiftSDKs(inArtifactBundle bundle: URL) throws(Error) -> [SwiftSDK] {
    let metadata: ArtifactBundleMetadata
    do {
      metadata = try SwiftPackageManager.parseArtifactBundle(bundle)
    } catch {
      throw Error(.failedToParseArtifactBundleInfo(bundle), cause: error)
    }

    // Each artifact bundle can contain multiple Swift SDKs
    var sdks: [SwiftSDK] = []
    for (name, artifact) in metadata.artifacts where artifact.type == .swiftSDK {
      for variant in artifact.variants {
        let artifactVariant = bundle / variant.path
        let manifest = try loadManifest(forSDKVariant: artifactVariant)

        for (triple, sdkManifest) in manifest.targetTriples {
          let sdk = SwiftSDK(
            supportedHostTriples: variant.supportedHostTriples,
            triple: triple,
            bundle: bundle,
            artifactVariant: artifactVariant,
            artifactIdentifier: name,
            sdk: sdkManifest
          )
          sdks.append(sdk)
        }
      }
    }

    return sdks
  }

  /// Loads the swift-sdk.json manifest file from the given Swift SDK artifact variant.
  static func loadManifest(forSDKVariant variant: URL) throws(Error) -> SwiftSDKManifest {
    let file = variant / "swift-sdk.json"
    let data = try Error.catch {
      try Data(contentsOf: file)
    }

    // Loosely check schema version
    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let schemaVersion = object[SwiftSDKManifest.CodingKeys.schemaVersion.rawValue] as? String
    {
      if !supportedSchemaVersions.contains(schemaVersion) {
        log.warning(
          """
          Unsupported Swift SDK schema version '\(schemaVersion)' in manifest \
          at '\(file.path)' (supported schema versions: \
          \(supportedSchemaVersions.joinedGrammatically())). Attempting to load \
          SDK anyway. Please create an issue at \
          https://github.com/moreSwift/swift-bundler/issues/new to notify us \
          about the new schema version
          """
        )
      }
    } else {
      log.warning("Failed to extract schemaVersion from Swift SDK manifest at '\(file.path)'")
    }

    return try Error.catch {
      try JSONDecoder().decode(SwiftSDKManifest.self, from: data)
    }
  }

  /// Gets a ready-to-use SDK silo for the given SDK.
  ///
  /// An SDK silo is a directory containing a single SDK artifact bundle. We
  /// use these to circumvent SwiftPM's SDK selection logic so that we can be
  /// sure that the SDK we have located matches the one that Swift decides to
  /// use. The main reason that this is necessary is that SwiftPM currently
  /// (as of 29/01/2025) doesn't support disambiguating between SDKs that have
  /// more than one supported target triple in common. The other reason is that
  /// we will be able to easily support user supplied SDKs at arbitrary locations. 
  ///
  /// We use symbolic links to efficiently construct silos.
  static func getPopulatedSDKSilo(forSDK sdk: SwiftSDK) throws(Error) -> URL {
    let silo = try Error.catch {
      try FileSystem.swiftSDKSiloDirectory(forArtifactIdentifier: sdk.artifactIdentifier)
    }

    // We add a stable hash to the end of the silo's name to prevent potential
    // race conditions if two distinct SDKs with the same identifier are used
    // in two concurrent Swift Bundler build invocations.
    let pathHash = UInt32(truncatingIfNeeded: sdk.bundle.path.stableHash)
    let pathHashString = String(format: "%08x", pathHash)
    let link = silo / "\(sdk.bundle.lastPathComponent)-\(pathHashString)"

    let destination = sdk.bundle
    if !link.exists() || link.actuallyResolvingSymlinksInPath() != destination {
      try Error.catch {
        // Even if the link exists, we could technically have hit a hash collision.
        // It should be exceedingly for hashes to clash at the same time as a race
        // condition, and if the hashes collide now then they'll collide every time,
        // so we just fix the link if it's wrong. This way, the only bug we're opening
        // ourselves to is race conditions, rather than race conditions AND hash
        // collisions. And we've successfully reduced the chance of race conditions
        // to basically zero assuming someone isn't intentionally trying to make the
        // hashes clash.
        if link.exists() {
          try FileManager.default.removeItem(at: link)
        }
        try FileManager.default.createSymbolicLink(
          at: link,
          withDestinationURL: destination
        )
      }
    }

    return silo
  }

  /// Attempts to detect the Swift compiler version used to generate a Swift
  /// Android SDK.
  ///
  /// This is a bit hacky and might break at some point, but our approach is
  /// to locate a known `swiftinterface` file and parse out the
  /// `swift-compiler-version` included in the comments at the top of the file.
  static func getCompilerVersionString(
    fromAndroidSDK sdk: SwiftSDK
  ) throws(Error) -> String {
    // TODO(stackotter): Implement proper triple parsing. I generally do things
    //   up-front, but this would probably take a little while to get right and
    //   this is only here to catch unintended usage of the function (isn't part
    //   of core functionality).
    guard sdk.triple.contains("-unknown-linux-android") else {
      throw Error(.cannotGetCompilerVersionStringFromNonAndroidSDK(sdk))
    }

    // Remove the API from the target triple
    // TODO(stackotter): Implement proper triple parsing so that we can drop
    //   the API version nicer
    let baseTriple = sdk.triple.trimmingCharacters(in: .decimalDigits)
    let interface = sdk.resourcesDirectory
      / "android/Swift.swiftmodule/\(baseTriple).swiftinterface"
    let interfaceContents = try Error.catch {
      try String(contentsOf: interface)
    }

    let commentPrefix = "// "
    let commentLines = interfaceContents.split(separator: "\n")
      .prefix { $0.starts(with: commentPrefix) }
      .map { $0.dropFirst(commentPrefix.count) }

    let tag = "swift-compiler-version: "
    guard
      let compilerVersionComment = commentLines.first(where: { $0.starts(with: tag) })
    else {
      throw Error(.couldNotLocateCompilerVersionString(sdk, interface))
    }

    // Trim in case there's a carriage return or other unexpected whitespace. We
    // aren't parsing something with a spec so we should be lenient.
    let compilerVersion = compilerVersionComment.dropFirst(tag.count)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    return compilerVersion
  }
}
