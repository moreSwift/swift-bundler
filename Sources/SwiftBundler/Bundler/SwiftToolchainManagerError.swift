import Foundation
import ErrorKit

extension SwiftToolchainManager {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``SwiftToolchainManager``.
  enum ErrorMessage: Throwable {
    case failedToLoadToolchainInfoPlist(_ infoPlist: URL)
    case toolchainMissingSwiftExecutable(toolchain: URL, swiftExecutable: URL)

    var userFriendlyMessage: String {
      switch self {
        case .failedToLoadToolchainInfoPlist(let infoPlist):
          return "Failed to load toolchain manifest at '\(infoPlist.path)'"
        case .toolchainMissingSwiftExecutable(let toolchain, let swiftExecutable):
          return """
            Toolchain at '\(toolchain.path)' is missing the Swift executable; \
            expected it to be at '\(swiftExecutable.path)'
            """
      }
    }
  }
}
