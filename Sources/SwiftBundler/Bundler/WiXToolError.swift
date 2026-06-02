import ErrorKit
import Foundation

extension WiXTool {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``WiXTool``.
  enum ErrorMessage: Throwable {
    case failedToDownloadWiXCLI
    case failedToLocateWiXCLI(directory: URL, guess: URL?)
    case invalidExtensionSpecifier(String)
    case invalidExtensionVersion(_ identifier: String, _ version: String)

    var userFriendlyMessage: String {
      switch self {
        case .failedToDownloadWiXCLI:
          return "Failed to download the WiX CLI"
        case .failedToLocateWiXCLI(let directory, let guess):
          var message = """
            Failed to locate wix CLI in unzipped package located at \
            \(directory.path)
            """
          if let guess {
            message += "; expected to find the CLI at \(guess.path)"
          }
          return message
        case .invalidExtensionSpecifier(let specifier):
          return """
            Got invalid WiX extension specifier '\(specifier)'; expected \
            '<identifier>/<version>' (e.g. 'WixToolset.Util.wixext/6.0.0')
            """
        case .invalidExtensionVersion(let identifier, let version):
          return "Got invalid version '\(version)' for WiX extension '\(identifier)'"
      }
    }
  }
}
