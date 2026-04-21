import Foundation

extension SwiftPackageManager {
  /// A package's original source.
  enum PackageSource: Codable, Sendable {
    /// A package loaded from a local path.
    case local(path: URL)
    /// A package loaded from a remote git repository.
    case remote(gitRepository: URL)
  }
}
