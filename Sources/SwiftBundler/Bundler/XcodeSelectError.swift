import Foundation
import ErrorKit

extension XcodeSelect {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``XcodeSelect``.
  enum ErrorMessage: Throwable {
    case nonExistentDeveloperDirectory(URL)

    var userFriendlyMessage: String {
      switch self {
        case .nonExistentDeveloperDirectory(let directory):
          return """
            xcode-select returned a non-existent developer directory; '\(directory.path)'
            """
      }
    }
  }
}
