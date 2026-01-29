import Foundation

/// A Swift SDK that can be used to cross-compile a SwiftPM product.
struct SwiftSDK: Hashable, Sendable {
  /// `nil` means assume that the host platform is supported.
  var supportedHostTriples: [String]?
  var triple: String

  var root: URL
  var resourcesDirectory: URL
  var staticResourcesDirectory: URL
  var includeSearchDirectories: [URL]
  var librarySearchDirectories: [URL]
  var toolsetFiles: [URL]

  var bundle: URL
  var artifactVariant: URL
  var artifactIdentifier: String

  /// A unique identifier for the SDK assuming that it was loaded from disk.
  /// Two non-equal programmatically-synthesized SDKs may have the same
  /// 'uniqueIdentifier'.
  var generallyUniqueIdentifier: String {
    let variantPath = artifactVariant.path(relativeTo: bundle)
    return "\(bundle.path):\(variantPath):\(triple)"
  }

  init(
    supportedHostTriples: [String]?,
    triple: String,
    bundle: URL,
    artifactVariant: URL,
    artifactIdentifier: String,
    sdk: SwiftSDKManifest.SDK
  ) {
    self.supportedHostTriples = supportedHostTriples
    self.triple = triple
    self.bundle = bundle
    self.artifactVariant = artifactVariant
    self.artifactIdentifier = artifactIdentifier
    root = artifactVariant / sdk.sdkRootPath

    // Ref: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0387-cross-compilation-destinations.md#swift-sdkjson-files
    if let resourcesPath = sdk.swiftResourcesPath {
      resourcesDirectory = artifactVariant / resourcesPath
    } else {
      resourcesDirectory = root / "usr/lib/swift"
    }
    if let staticResourcesPath = sdk.swiftStaticResourcesPath {
      staticResourcesDirectory = artifactVariant / staticResourcesPath
    } else {
      staticResourcesDirectory = root / "usr/lib/swift_static"
    }
    if let includeSearchPaths = sdk.includeSearchPaths {
      includeSearchDirectories = includeSearchPaths.map { [artifactVariant] in
        artifactVariant / $0
      }
    } else {
      includeSearchDirectories = [root / "usr/include"]
    }
    if let librarySearchPaths = sdk.librarySearchPaths {
      librarySearchDirectories = librarySearchPaths.map { [artifactVariant] in
        artifactVariant / $0
      }
    } else {
      librarySearchDirectories = [root / "usr/lib"]
    }
    if let toolsetPaths = sdk.toolsetPaths {
      toolsetFiles = toolsetPaths.map { [artifactVariant] in
        artifactVariant / $0
      }
    } else {
      toolsetFiles = []
    }
  }

  /// Gets whether the SDK supports the given host triple.
  func supportsHostTriple(_ triple: LLVMTargetTriple) -> Bool {
    if let supportedHostTriples {
      supportedHostTriples.contains(triple.description)
    } else {
      true
    }
  }
}

/// Custom `Encodable` implementation to represent URLs as paths instead of
/// `file://` URLs.
extension SwiftSDK: Encodable {
  enum CodingKeys: String, CodingKey {
    case supportedHostTriples
    case triple
    case root
    case resourcesDirectory
    case staticResourcesDirectory
    case includeSearchDirectories
    case librarySearchDirectories
    case toolsetFiles
    case bundle
    case artifactVariant
    case artifactIdentifier
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(supportedHostTriples, forKey: .supportedHostTriples)
    try container.encode(triple, forKey: .triple)
    try container.encode(root.path, forKey: .root)
    try container.encode(resourcesDirectory.path, forKey: .resourcesDirectory)
    try container.encode(staticResourcesDirectory.path, forKey: .staticResourcesDirectory)
    try container.encode(includeSearchDirectories.map(\.path), forKey: .includeSearchDirectories)
    try container.encode(librarySearchDirectories.map(\.path), forKey: .librarySearchDirectories)
    try container.encode(toolsetFiles.map(\.path), forKey: .toolsetFiles)
    try container.encode(bundle.path, forKey: .bundle)
    try container.encode(artifactVariant.path, forKey: .artifactVariant)
    try container.encode(artifactIdentifier, forKey: .artifactIdentifier)
  }
}
