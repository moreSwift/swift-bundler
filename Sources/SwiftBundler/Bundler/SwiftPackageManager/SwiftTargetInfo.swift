import Foundation

/// An extremely simplified version of the output of `swift -print-target-info`.
///
/// Kept simple to minimize the chance that breaking changes in the command's output
/// might break Swift Bundler.
struct SwiftTargetInfo: Codable {
  /// Info about a target platform.
  struct Target: Codable {
    /// The platform's versioned triple.
    var triple: String
    /// The platform's unversioned triple.
    var unversionedTriple: String
  }

  /// Paths to various parts of a toolchain.
  struct Paths: Codable {
    var runtimeLibraryPaths: [URL]
    var runtimeLibraryImportPaths: [URL]
    var runtimeResourcePath: URL
  }

  /// The compiler version string.
  var compilerVersion: String
  /// Info about the target platform.
  var target: Target
  /// Paths to various parts of the current toolchain.
  var paths: Paths
}
