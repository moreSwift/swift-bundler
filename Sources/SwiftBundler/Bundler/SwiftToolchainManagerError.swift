import Foundation
import ErrorKit

extension SwiftToolchainManager {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``SwiftToolchainManager``.
  enum ErrorMessage: Throwable {
    case failedToLoadToolchainInfoPlist(_ infoPlist: URL)
    case toolchainMissingSwiftExecutable(toolchain: URL, swiftExecutable: URL)
    case failedToParseSwiftCompilerVersionString(
      versionString: String,
      message: String
    )
    case cannotDoToolchainMatchingForNonAndroidSDKs(SwiftSDK)
    case failedToFindToolchainMatchingAndroidSDK(SwiftSDK)

    var userFriendlyMessage: String {
      switch self {
        case .failedToLoadToolchainInfoPlist(let infoPlist):
          return "Failed to load toolchain manifest at '\(infoPlist.path)'"
        case .toolchainMissingSwiftExecutable(let toolchain, let swiftExecutable):
          return """
            Toolchain at '\(toolchain.path)' is missing the Swift executable; \
            expected it to be at '\(swiftExecutable.path)'
            """
        case .failedToParseSwiftCompilerVersionString(let versionString, let message):
          return """
            Could not parse Swift compiler version string '\(versionString)': \
            \(message)
            """
        case .cannotDoToolchainMatchingForNonAndroidSDKs(let sdk):
          return """
            Cannot do toolchain discovery for non-Android Swift SDKs; tried \
            for '\(sdk.generallyUniqueIdentifier)'
            """
        case .failedToFindToolchainMatchingAndroidSDK(let sdk):
          return """
            Failed to find toolchain compatible with Android SDK \
            '\(sdk.generallyUniqueIdentifier)'
            """
      }
    }
  }
}
