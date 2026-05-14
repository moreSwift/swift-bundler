import ErrorKit
import Foundation

extension MSIXBundler {
  typealias Error = RichError<ErrorMessage>

  enum ErrorMessage: Throwable {
    case msixConfigurationRequired
    case failedToLoadIcon(URL)
    case failedToEncodePNG
    case failedToCreateAssetsDirectory(URL)
    case failedToRenameGenericBundle(source: URL, destination: URL)

    var userFriendlyMessage: String {
      switch self {
        case .msixConfigurationRequired:
          return "The MSIX configuration for the target package is required but was not found"
        case .failedToLoadIcon(let icon):
          return "Failed to load icon at '\(icon.path(relativeTo: .currentDirectory))'"
        case .failedToEncodePNG:
          return "Failed to encode PNG file"
        case .failedToCreateAssetsDirectory(let directory):
          return
            "Failed to create Assets directory at '\(directory.path(relativeTo: .currentDirectory))'"
        case .failedToRenameGenericBundle(let source, let destination):
          return """
            Failed to move generic bundle from '\(source.path(relativeTo: .currentDirectory))' \
            to '\(destination.path(relativeTo: .currentDirectory))'
            """
      }
    }
  }
}
