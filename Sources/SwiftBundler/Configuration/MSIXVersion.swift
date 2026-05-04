import Foundation

/// A version of the MSIX package.
struct MSIXVersion: Codable, Sendable, TriviallyFlattenable {
  /// The JSON schema for a MSIX version.
  private static var schema = """
    {
      "type": "string",
      "pattern": "^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$"
    }
    """

  var major: Int
  var minor: Int
  var build: Int
  var revision: Int

  var stringValue: String {
    "\(major).\(minor).\(build).\(revision)"
  }

  init(major: Int, minor: Int, build: Int, revision: Int) {
    self.major = major
    self.minor = minor
    self.build = build
    self.revision = revision
  }

  init(from decoder: any Decoder) throws {
    let singleValueContainer = try decoder.singleValueContainer()
    let versionString = try singleValueContainer.decode(String.self)
    let components = versionString.split(separator: ".").map { String($0) }
    guard components.count == 4,
      let major = Int(components[0]),
      let minor = Int(components[1]),
      let build = Int(components[2]),
      let revision = Int(components[3])
    else {
      throw DecodingError.dataCorruptedError(
        in: singleValueContainer,
        debugDescription:
          "Version string must be in the format 'major.minor.build.revision' with all components being integers."
      )
    }
    self.major = major
    self.minor = minor
    self.build = build
    self.revision = revision
  }

  func encode(to encoder: any Encoder) throws {
    var singleValueContainer = encoder.singleValueContainer()
    try singleValueContainer.encode(stringValue)
  }
}
