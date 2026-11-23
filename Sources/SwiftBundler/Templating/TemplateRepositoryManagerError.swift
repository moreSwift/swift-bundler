import Foundation
import ErrorKit

extension TemplateRepositoryManager {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``TemplateRepositoryManager``.
  enum ErrorMessage: Throwable {
    case failedToEnumerateTemplates
    case failedToPullLatestTemplates(_ checkout: URL)
    case failedToCloneTemplateRepository(URL)

    var userFriendlyMessage: String {
      switch self {
        case .failedToEnumerateTemplates:
          return "Failed to enumerate templates in template repository."
        case .failedToPullLatestTemplates(let checkout):
          return "Failed to update template repository at '\(checkout)'"
        case .failedToCloneTemplateRepository(let url):
          return "Failed to clone template repository from '\(url)'"
      }
    }
  }
}
