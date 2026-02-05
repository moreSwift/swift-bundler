import Foundation

/// A parsed SwiftPM artifactbundle info.json file.
struct ArtifactBundleMetadata: Decodable, Equatable, Sendable {
  struct Artifact: Decodable, Equatable, Sendable {
    var variants: [Variant]
    var version: String
    var type: ArtifactType

    struct Variant: Decodable, Equatable, Sendable {
      var path: String
      var supportedHostTriples: [String]?
    }
  }

  enum ArtifactType: Decodable, Hashable, Sendable {
    case swiftSDK
    case unknown(String)

    init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)

      switch value {
        case "swiftSDK":
          self = .swiftSDK
        default:
          self = .unknown(value)
      }
    }
  }

  var schemaVersion: String
  var artifacts: [String: Artifact]
}
