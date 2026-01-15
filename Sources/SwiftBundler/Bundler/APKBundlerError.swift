import Foundation
import ErrorKit

extension APKBundler {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``APKBundler``.
  enum ErrorMessage: Throwable {
    var userFriendlyMessage: String {
      switch self {}
    }
  }
}
