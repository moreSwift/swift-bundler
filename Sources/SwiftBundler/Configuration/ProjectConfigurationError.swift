import Foundation
import ErrorKit

extension ProjectConfiguration {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``ProjectConfiguration``.
  enum ErrorMessage: Throwable {
    case invalidGitURL(String)
    case invalidURL(String)
    case projectBuilderNotASwiftFile(String)

    var userFriendlyMessage: String {
      switch self {
        case .invalidGitURL(let url):
          return "'\(url)' is not a valid URL"
        case .invalidURL(let url):
          return "'\(url)' is not a valid URL"
        case .projectBuilderNotASwiftFile(let builder):
          return """
            Library builders must be swift files, and '\(builder)' isn't one
            """
      }
    }
  }
}
