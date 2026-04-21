import Foundation

extension SwiftPackageManager {
  /// A package target.
  struct Target: Codable, Sendable {
    /// The target's name.
    var name: String
    /// The kind of target.
    var kind: Kind
    /// The directory containing the target's sources.
    var directory: URL
    /// The target's dependency.
    var dependencies: [TargetDependency]

    /// The kind of a target.
    enum Kind: String, Codable, Sendable, Hashable {
      /// A library target.
      case library
      /// An executable target.
      case executable
      /// A system target.
      case systemTarget
      /// A test target.
      case test
      /// A macro target.
      case macro
      /// A plugin target.
      case plugin
    }
  }
}
