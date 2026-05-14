import Foundation

/// A version with four components used in MSIX manifests.
struct MSIXVersion: CustomStringConvertible, Codable, Sendable, TriviallyFlattenable {
  /// The JSON schema for a MSIX version.
  ///
  /// This RegEx just ensures all components are valid UInt16 values.
  private static var schema = """
    {
      "type": "string",
      "pattern": "^(0|[1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])(\\.(0|[1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])){3}$"
    }
    """

  var major: UInt16
  var minor: UInt16
  var build: UInt16
  var revision: UInt16

  var description: String {
    "\(major).\(minor).\(build).\(revision)"
  }

  init(major: UInt16, minor: UInt16, build: UInt16, revision: UInt16) {
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
      let major = UInt16(components[0]),
      let minor = UInt16(components[1]),
      let build = UInt16(components[2]),
      let revision = UInt16(components[3])
    else {
      throw DecodingError.dataCorruptedError(
        in: singleValueContainer,
        debugDescription:
          "Version string must be in the format 'major.minor.build.revision' with all components being 16-bit unsigned integers."
      )
    }
    self.major = major
    self.minor = minor
    self.build = build
    self.revision = revision
  }

  func encode(to encoder: any Encoder) throws {
    var singleValueContainer = encoder.singleValueContainer()
    try singleValueContainer.encode(description)
  }
}
