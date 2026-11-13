import Foundation
import ErrorKit

extension CLIConfiguration {
  typealias Error = RichError<ErrorMessage>

  /// An error meesage related to ``CLIConfiguration``.
  enum ErrorMessage: Throwable {
    case invalidRPMRequirement(String)

    var userFriendlyMessage: String {
      switch self {
        case .invalidRPMRequirement(let requirement):
          return "RPM requirement invalid, contains restricted characters: \(requirement)"
      }
    }
  }
}
