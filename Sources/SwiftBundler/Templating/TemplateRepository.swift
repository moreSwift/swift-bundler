import Foundation

/// A template repository.
struct TemplateRepository {
  /// The repository's source: either a remote git repository URL or a local
  /// directory.
  var source: URL
  /// The template repository's local checkout on-disk.
  var checkout: URL

  /// Enumerates the repository's templates.
  /// - Returns: The available templates.
  func enumerateTemplates()
    throws(TemplateRepositoryManager.Error) -> [Template]
  {
    do {
      let contents = try FileManager.default.contentsOfDirectory(
        at: checkout,
        includingPropertiesForKeys: nil,
        options: []
      )
      var templates: [Template] = []

      // Enumerate templates
      for directory in contents {
        guard directory.exists(withType: .directory) else {
          continue
        }

        let templateName = directory.lastPathComponent

        // Skip `Base` template, `VSCode` template, and `.git` directory
        guard
          templateName != "Base" && templateName != "VSCode" && !templateName.starts(with: ".")
        else {
          continue
        }

        // Load the template manifest file
        let manifestFile = directory.appendingPathComponent("Template.toml")
        let manifest = try TemplateManifest.load(from: manifestFile, template: templateName)

        let template = Template(name: templateName, manifest: manifest)
        templates.append(template)
      }

      return templates
    } catch {
      throw TemplateRepositoryManager.Error(
        .failedToEnumerateTemplates,
        cause: error
      )
    }
  }
}
