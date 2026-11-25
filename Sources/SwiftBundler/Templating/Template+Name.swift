import ArgumentParser

extension Template {
  /// A template name. Only alphanumeric ASCII characters, hyphens,
  /// and underscores are allowed. Leading hyphens are disallowed.
  struct Name: Codable, Hashable, Sendable, CustomStringConvertible,
    ExpressibleByArgument, TriviallyFlattenable
  {
    /// We need the same validation as a template repository name, so we just
    /// use a template repository name under the hood.
    private var _name: TemplateRepository.Name

    /// The underlying validated name.
    var name: String {
      _name.name
    }

    /// Creates a validated template name.
    /// - Returns: `nil` if the name is invalid.
    init?(_ name: String) {
      guard let name = TemplateRepository.Name(name) else {
        return nil
      }
      _name = name
    }

    init?(argument: String) {
      guard let name = TemplateRepository.Name(argument: argument) else {
        return nil
      }
      _name = name
    }

    var description: String {
      _name.description
    }

    // newtype support would be great right about now...

    init(from decoder: any Decoder) throws {
      do {
        _name = try TemplateRepository.Name(from: decoder)
      } catch let error as TemplateRepositoryManager.Error {
        switch error.message {
          case .invalidTemplateRepositoryName(let name):
            throw TemplateRepositoryManager.Error(
              .invalidTemplateName(name)
            )
          default:
            throw error
        }
      }
    }

    func encode(to encoder: any Encoder) throws {
      try _name.encode(to: encoder)
    }
  }
}
