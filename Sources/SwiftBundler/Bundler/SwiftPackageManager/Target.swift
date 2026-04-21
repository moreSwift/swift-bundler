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
      /// A binary target.
      case binary
      /// A snippet target.
      case snippet

      /// Converts a manifest target type to a package graph target kind. Returns nil
      /// in case of unrecognized target types.
      init?(from manifestTargetType: PackageManifest.TargetType) {
        switch manifestTargetType {
          case .executable:
            self = .executable
          case .library:
            self = .library
          case .systemTarget:
            self = .systemTarget
          case .test:
            self = .test
          case .macro:
            self = .macro
          case .plugin:
            self = .plugin
          case .snippet:
            self = .snippet
          case .binary:
            self = .binary
          case .other(_):
            return nil
        }
      }
    }
  }
}
