import Foundation

/// A project template.
struct Template {
  /// The template's name.
  var name: String
  /// The location of the template.
  var location: URL
  /// The repository that the template came from.
  var repository: TemplateRepository.Name
  /// The template's manifest.
  var manifest: TemplateManifest
}
