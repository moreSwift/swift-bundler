import ErrorKit

extension WindowsCodeSigner {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``WindowsCodeSigner``.
  enum ErrorMessage: Throwable {
    case failedToLoadCertificateStore(_ identifier: String)

    var userFriendlyMessage: String {
      switch self {
        case .failedToLoadCertificateStore(let identifier):
          return "Failed to load current user certificate store named '\(identifier)'"
      }
    }
  }
}
