import Foundation

/// A project builder definition.
@Configuration(overlayable: false)
struct BuilderConfiguration: Codable {
  /// The executable product corresponding to this builder.
  var product: String
  /// The kind of builder.
  var kind: BuilderKind

  /// A kind of builder.
  enum BuilderKind: String, Codable, TriviallyFlattenable {
    /// A builder that builds all products in a given project at the same time
    /// rather than building individual products on command.
    case wholeProject
  }
}
