import ErrorKit
import Version

extension NuGetTool {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``NuGetTool``.
  enum ErrorMessage: Throwable {
    case failedToDownloadNuGetCLI
    case failedToInstallPackage(String, Version?)

    var userFriendlyMessage: String {
      switch self {
        case .failedToDownloadNuGetCLI:
          return "Failed to download the NuGet CLI"
        case .failedToInstallPackage(let name, let version):
          if let version {
            return "Failed to install \(name) @ \(version)"
          } else {
            return "Failed to install \(name)"
          }
      }
    }
  }
}
