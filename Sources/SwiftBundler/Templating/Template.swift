import Foundation

/// A project template.
struct Template {
  /// The template's name.
  var name: Template.Name
  /// The location of the template.
  var location: URL
  /// The repository that the template came from.
  var repository: TemplateRepository
  /// The template's manifest.
  var configuration: TemplateConfiguration.Flat

  /// Whether the template is visible outside of its template repository or not.
  var isPublic: Bool {
    configuration.visibility != .internal
  }
}
