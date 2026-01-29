import Foundation

struct SwiftSDKManifest: Decodable {
  var schemaVersion: String
  var targetTriples: [String: SDK]

  // Exists to make the coding keys accessible from outside of the type.
  enum CodingKeys: String, CodingKey {
    case schemaVersion
    case targetTriples
  }

  struct SDK: Decodable {
    var sdkRootPath: String
    var swiftResourcesPath: String?
    var swiftStaticResourcesPath: String?
    var includeSearchPaths: [String]?
    var librarySearchPaths: [String]?
    var toolsetPaths: [String]?
  }
}
