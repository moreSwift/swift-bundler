import ErrorKit
import Foundation

extension WindowsManifestTool {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``WindowsManifestTool``.
  enum ErrorMessage: Throwable {
    case failedToEncodeApplicationManifest(executable: URL)
    
    var userFriendlyMessage: String {
      switch self {
        case .failedToEncodeApplicationManifest(let executable):
          let path = executable.path(relativeTo: .currentDirectory)
          return "Failed to encode application manifest for executable at '\(path)'"
      }
    }
  }
}
