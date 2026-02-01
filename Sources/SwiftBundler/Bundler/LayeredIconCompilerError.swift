import ErrorKit
import Foundation

extension LayeredIconCompiler {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``LayeredIconCompiler``.
  enum ErrorMessage: Throwable {
    case notAnIconFile(URL)
    case failedToCreateIconDirectory(URL)
    case failedToCopyFile(URL, URL)
    case failedToCompileIcon
    case failedToDecodePartialInfoPlist(URL)
    case failedToCompileICNS
    case failedToRemoveIconDirectory(URL)

    var userFriendlyMessage: String {
      switch self {
        case .notAnIconFile(let file):
          return
            "Expected icon file to have a '.icon' file extension, but got '\(file.path(relativeTo: .currentDirectory))'"
        case .failedToCreateIconDirectory(let directory):
          return """
            Failed to create a temporary icon directory at '\(directory)'
            """
        case .failedToCopyFile(let from, let to):
          return """
            Failed to copy file from '\(from.path(relativeTo: .currentDirectory))' to '\(to)'
            """
        case .failedToCompileIcon:
          return "Failed to create icon files"
        case .failedToDecodePartialInfoPlist(let plistPath):
          return """
            Failed to decode the partial Info.plist at '\(plistPath)'
            """
        case .failedToCompileICNS:
          return "Failed to convert the icon to ICNS format"
        case .failedToRemoveIconDirectory(let directory):
          return """
            Failed to remove the temporary icon directory at '\(directory)'
            """
      }
    }
  }
}
