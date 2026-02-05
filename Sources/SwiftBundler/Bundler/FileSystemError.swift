import Foundation
import ErrorKit

extension FileSystem {
  typealias Error = RichError<ErrorMessage>

  enum ErrorMessage: Throwable {
    case failedToGetCacheDirectory
    case failedToCreateSwiftSDKSilosDirectory
    case failedToCreateSwiftSDKSiloDirectory(URL)

    var userFriendlyMessage: String {
      switch self {
        case .failedToGetCacheDirectory:
          return "Failed to locate or create a suitable cache directory"
        case .failedToCreateSwiftSDKSilosDirectory:
          return "Failed to create directory for Swift SDK silos"
        case .failedToCreateSwiftSDKSiloDirectory(let silo):
          return "Failed to create Swift SDK silo at '\(silo.path)'"
      }
    }
  }
}
