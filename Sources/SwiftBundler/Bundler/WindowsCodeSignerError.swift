import ErrorKit
import Foundation

extension WindowsCodeSigner {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``WindowsCodeSigner``.
  enum ErrorMessage: Throwable {
    case failedToLoadCertificateStore(_ identifier: String)
    case identityNotFound(_ searchTerm: String)
    case failedToDownloadArtifactSigningClient
    case fileDoesNotExist(URL)

    var userFriendlyMessage: String {
      switch self {
        case .failedToLoadCertificateStore(let identifier):
          return "Failed to load current user certificate store named '\(identifier)'"
        case .identityNotFound(let searchTerm):
          return "Code signing identity not found for search term '\(searchTerm)'"
        case .failedToDownloadArtifactSigningClient:
          return "Failed to download Azure Artifact Signing Client"
        case .fileDoesNotExist(let file):
          return "File does not exist at '\(file.path)'"
      }
    }
  }
}
