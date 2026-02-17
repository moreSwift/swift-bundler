import Foundation

/// A Swift toolchain.
struct SwiftToolchain: Hashable, Sendable {
  /// The root directory of the toolchain.
  var root: URL
  /// The toolchain's display name.
  var displayName: String
  /// The toolchain's Swift compiler's version string (from
  /// `swift -print-target-info`).
  var compilerVersionString: String
  /// The kind of toolchain.
  var kind: Kind

  /// The kind of a Swift toolchain.
  enum Kind: String, Hashable, Sendable, Encodable {
    /// An Xcode toolchain (e.g. the one at
    /// `Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain`).
    case xcodeToolchain
    /// An Xcode CommandLineTools installation.
    case xcodeCommandLineTools
    /// A toolchain installed from the swift.org installers.
    case standalone
    /// A toolchain that doesn't match any pattern known to Swift Bundler.
    case unknown
  }

  /// The location of the toolchain's `swift` executable.
  var swiftExecutable: URL {
    Self.swiftExecutable(forToolchainWithRoot: root)
  }

  /// Computes the location of a toolchain's `swift` executable given its root
  /// directory.
  static func swiftExecutable(forToolchainWithRoot root: URL) -> URL {
    root / "usr/bin/swift"
  }
}

/// Custom `Encodable` implementation to represent URLs as paths instead of
/// `file://` URLs.
extension SwiftToolchain: Encodable {
  enum CodingKeys: String, CodingKey {
    case root
    case displayName
    case compilerVersionString
    case kind
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(root.path, forKey: .root)
    try container.encode(displayName, forKey: .displayName)
    try container.encode(compilerVersionString, forKey: .compilerVersionString)
    try container.encode(kind, forKey: .kind)
  }
}
