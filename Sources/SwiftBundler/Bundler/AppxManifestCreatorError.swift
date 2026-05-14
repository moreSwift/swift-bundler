import ErrorKit
import Foundation

extension AppxManifestCreator {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``AppxManifestCreator``.
  enum ErrorMessage: Throwable {
    case msixFieldsMissing
    case unknownArchitecture
    case failedToWriteManifest(file: URL)
    case xmlEncodingFailed

    var userFriendlyMessage: String {
      switch self {
        case .msixFieldsMissing:
          return "Missing required MSIX fields"
        case .unknownArchitecture:
          return
            "There are either multiple architectures or no architectures. MSIX packaging requires a single architecture."
        case .failedToWriteManifest(let file):
          return "Failed to write manifest to \(file.path)"
        case .xmlEncodingFailed:
          return "Failed to encode manifest to XML"
      }
    }
  }
}
