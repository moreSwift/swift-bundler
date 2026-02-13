import Foundation
import ErrorKit

extension AppleDeviceManager {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``AppleDeviceManager``.
  enum ErrorMessage: Throwable {
    case failedToListXcodeDestinations
    case failedToCreateDummyProject
    case failedToParseXcodeDestinationList(
      _ xcodeDestinationList: String,
      reason: String
    )
    case failedToParseXcodeDestination(
      _ xcodeDestination: String,
      reason: String
    )

    var userFriendlyMessage: String {
      switch self {
        case .failedToCreateDummyProject:
          return "Failed to create dummy project required to list Xcode destinations"
        case .failedToListXcodeDestinations:
          return "Failed to list Xcode destinations"
        case .failedToParseXcodeDestinationList(_, let reason):
          return "Failed to parse Xcode destination list: \(reason)"
        case .failedToParseXcodeDestination(_, let reason):
          return "Failed to parse Xcode destination: \(reason)"
      }
    }
  }
}
