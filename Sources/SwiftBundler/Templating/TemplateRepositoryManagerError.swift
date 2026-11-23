import Foundation
import ErrorKit

extension TemplateRepositoryManager {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``TemplateRepositoryManager``.
  enum ErrorMessage: Throwable {
    case failedToEnumerateTemplates
    case failedToPullLatestTemplates(_ checkout: URL)
    case failedToCloneTemplateRepository(URL)
    case noSuchRepository(TemplateRepository.Name)
    case invalidTemplateRepositoryName(String)
    case noSuchTemplate(String)
    case ambiguousTemplateName(
      String,
      [(repo: TemplateRepository.Name, template: Template)]
    )

    var userFriendlyMessage: String {
      switch self {
        case .failedToEnumerateTemplates:
          return "Failed to enumerate templates in template repository."
        case .failedToPullLatestTemplates(let checkout):
          return "Failed to update template repository at '\(checkout)'"
        case .failedToCloneTemplateRepository(let url):
          return "Failed to clone template repository from '\(url)'"
        case let .noSuchTemplate(template):
          return "No such template '\(template)'"
        case .noSuchRepository(let name):
          return "No such repository '\(name)'"
        case .invalidTemplateRepositoryName(let name):
          return """
            Invalid template repository name '\(name)'; only alphanumeric \
            characters, underscores, and hyphens are allowed
            """
        case .ambiguousTemplateName(let name, let candidates):
          let candidateString = candidates.map { (repo, template) in
            "'\(template.name)' from '\(repo)'"
          }.joinedGrammatically()
          return """
            Multiple templates are called '\(name)': \(candidateString)
            """
      }
    }
  }
}
