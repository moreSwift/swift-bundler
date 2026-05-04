import Foundation

/// A dependency required by the MSIX package.
struct MSIXDependency: Codable, Sendable, TriviallyFlattenable {
  enum CodingKeys: String, CodingKey {
    case name
    case minimumVersion = "minimum_version"
    case publisher
  }

  /// The name of the dependency.
  var name: String
  /// The minimum version of the dependency required by the app.
  var minimumVersion: MSIXVersion
  /// The publisher of the dependency.
  var publisher: String
}
