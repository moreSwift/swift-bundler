import Foundation

/// A template repository.
struct TemplateRepository: Codable {
  /// The template repository's name. This is set when adding a repository.
  var name: Name
  /// The repository's source: either a remote git repository URL or a local
  /// directory.
  var source: URL
  /// The template repository's local checkout on-disk.
  var checkout: URL
  /// The kind of template repository.
  var kind: Kind

  /// Whether the repository is remote or not. For now this just means that
  /// the ``kind`` is ``Kind/remoteGit``.
  var isRemote: Bool {
    kind == .remoteGit
  }

  /// A kind of template repository.
  enum Kind: String, Codable {
    /// A remote template repository stored with git.
    case remoteGit
    /// A local template repository represented as a path.
    case local
  }

  /// Enumerates the repository's templates.
  /// - Returns: The available templates.
  func enumerateTemplates()
    throws(TemplateRepositoryManager.Error) -> [Template.Name: Template]
  {
    do {
      let file = checkout / "BundlerTemplates.toml"
      let configuration = try TemplateRepositoryConfiguration.load(from: file)

      return configuration.templates.mapValues { (name, configuration) in
        Template(
          name: name,
          location: checkout / configuration.path,
          repository: self,
          configuration: configuration
        )
      }
    } catch {
      throw TemplateRepositoryManager.Error(
        .failedToEnumerateTemplates,
        cause: error
      )
    }
  }

  /// Resolves a template by name.
  /// - Parameter name: The template's name.
  /// - Returns: The template.
  func resolveTemplate(_ name: Template.Name)
    throws(TemplateRepositoryManager.Error) -> Template
  {
    let templates = try enumerateTemplates()
    guard let template = templates[name] else {
      throw TemplateRepositoryManager.Error(
        .noSuchTemplate(name)
      )
    }
    return template
  }
}
