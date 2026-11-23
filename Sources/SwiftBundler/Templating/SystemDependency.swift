import Foundation

/// A system dependency required by a template.
struct SystemDependency: Codable {
  /// The name (or names separated by spaces) of the brew package/s that satisfies this dependency.
  var brew: String?
}
