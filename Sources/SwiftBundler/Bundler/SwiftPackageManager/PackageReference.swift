extension SwiftPackageManager {
  /// A reference to a unique package.
  struct PackageReference: Codable, Sendable, Hashable, CustomStringConvertible {
    /// The package's identity.
    var identity: String

    /// Creates a package reference from a package identity.
    init(identity: String) {
      self.identity = identity
    }

    /// Creates a package reference from a package name. This reference
    /// may only be valid within the package itself, as the identity of
    /// a package can change depending on how it was depended upon.
    init(name: String) {
      self.identity = packageIdentity(forPackageWithName: name)
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      self.init(identity: try container.decode(String.self))
    }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(identity)
    }

    var description: String {
      identity
    }
  }
}
