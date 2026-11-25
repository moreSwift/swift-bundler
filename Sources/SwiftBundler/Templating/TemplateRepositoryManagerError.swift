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
    case invalidTemplateName(String)
    case invalidOptionalOverlayName(String)
    case noSuchTemplate(Template.Name)
    case ambiguousTemplateName(
      Template.Name,
      [(repo: TemplateRepository.Name, template: Template)]
    )
    case repositoryNameNotUnique(TemplateRepository.Name)
    case failedToLoadTemplateRepositoryConfiguration(URL)
    case nonExistentBaseTemplate(
      template: Template.Name,
      base: Template.Name
    )
    case selfReferentialTemplate(
      template: Template.Name,
      path: [Template.Name]
    )

    var userFriendlyMessage: String {
      switch self {
        case .failedToEnumerateTemplates:
          return "Failed to enumerate templates in template repository."
        case .failedToPullLatestTemplates(let checkout):
          return "Failed to update template repository at '\(checkout)'"
        case .failedToCloneTemplateRepository(let url):
          return "Failed to clone template repository from '\(url)'"
        case .noSuchTemplate(let template):
          return "No such template '\(template)'"
        case .noSuchRepository(let name):
          return "No such repository '\(name)'"
        case .invalidTemplateRepositoryName(let name):
          return """
            Invalid template repository name '\(name)'; only alphanumeric \
            ASCII characters, underscores, and non-leading hyphens are allowed
            """
        case .invalidTemplateName(let name):
          return """
            Invalid template name '\(name)'; only alphanumeric \
            ASCII characters, underscores, and non-leading hyphens are allowed
            """
        case .invalidOptionalOverlayName(let name):
          return """
            Invalid template overlay name '\(name)'; only alphanumeric \
            ASCII characters, underscores, and non-leading hyphens are allowed
            """
        case .ambiguousTemplateName(let name, let candidates):
          let candidateString = candidates.map { (repo, template) in
            "'\(template.name)' from '\(repo)'"
          }.joinedGrammatically()
          return """
            Multiple templates are called '\(name)': \(candidateString)
            """
        case .repositoryNameNotUnique(let name):
          return "A template repository already exists with name '\(name)'"
        case .failedToLoadTemplateRepositoryConfiguration(let file):
          return "Failed to load template repository configuration file at '\(file.path)'"
        case .nonExistentBaseTemplate(let template, let base):
          return "Template '\(template)' inherits from non-existent base template '\(base)'"
        case .selfReferentialTemplate(let template, let path):
          let cycle = path.map { templateName in
            "'\(templateName)'"
          }.joined(separator: " -> ")
          return "Template '\(template)' inherits from itself; \(cycle)"
      }
    }
  }
}
