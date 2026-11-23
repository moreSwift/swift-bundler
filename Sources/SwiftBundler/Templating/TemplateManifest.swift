import Foundation
import TOMLKit
import Version

/// The contents of a template's manifest file.
struct TemplateManifest: Codable {
  /// A short description of the package.
  var description: String
  /// The list of supported platforms.
  var platforms: [String]
  /// The minimum Swift version required to use the template.
  var minimumSwiftVersion: Version
  /// The system dependencies required by this template (keyed by the user-facing dependency name).
  var systemDependencies: [String: SystemDependency]?

  private enum CodingKeys: String, CodingKey {
    case description
    case platforms
    case minimumSwiftVersion = "minimum_swift_version"
    case systemDependencies = "system_dependencies"
  }

  /// Loads a template's manifest file.
  /// - Parameters:
  ///   - file: The manifest file to load.
  ///   - template: The name of the template that the manifest is for.
  /// - Returns: The loaded manifest, or a failure if the file could not be
  ///   read or decoded.
  static func load(from file: URL, template: String) throws(Templater.Error) -> TemplateManifest {
    let contents: String
    do {
      contents = try String(contentsOf: file)
    } catch {
      throw Templater.Error(
        .failedToReadTemplateManifest(template: template, manifest: file),
        cause: error
      )
    }

    let manifest: TemplateManifest
    do {
      var decoder = TOMLDecoder()
      decoder.userInfo[.decodingMethod] = DecodingMethod.tolerant
      manifest = try decoder.decode(TemplateManifest.self, from: contents)
    } catch {
      throw Templater.Error(
        .failedToDecodeTemplateManifest(template: template, manifest: file),
        cause: error
      )
    }

    return manifest
  }
}
