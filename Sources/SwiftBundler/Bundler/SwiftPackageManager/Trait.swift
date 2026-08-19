import Foundation

extension SwiftPackageManager {
  /// A package trait.
  struct Trait: Codable, Sendable {
    /// The name of the trait (used to reference the trait in package manifests).
    var name: String
    /// The traits human-facing description.
    var description: String?
    /// Traits that this trait transitively enables.
    var enabledTraits: [String]
  }
}
