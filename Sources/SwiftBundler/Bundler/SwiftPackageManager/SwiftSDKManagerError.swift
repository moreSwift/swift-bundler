import Foundation
import ErrorKit

extension SwiftSDKManager {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``SwiftSDKManager``.
  enum ErrorMessage: Throwable {
    case failedToEnumerateSDKs(_ directory: URL)
    case failedToParseArtifactBundleInfo(_ bundle: URL)
    case noSDKsMatchQuery(
      hostPlatform: HostPlatform,
      hostArchitecture: BuildArchitecture,
      targetTriple: LLVMTargetTriple
    )
    case cannotGetCompilerVersionStringFromNonAndroidSDK(SwiftSDK)
    case couldNotLocateCompilerVersionString(SwiftSDK, _ interface: URL)

    var userFriendlyMessage: String {
      switch self {
        case .failedToEnumerateSDKs(let directory):
          return "Failed to enumerate SDKs in '\(directory.path)'"
        case .failedToParseArtifactBundleInfo(let bundle):
          return "Failed to parse info.json of artifactbundle at '\(bundle.path)'"
        case .noSDKsMatchQuery(let hostPlatform, let hostArchitecture, let targetTriple):
          return """
            No SDKs match host platform '\(hostPlatform.platform.displayName)', \
            host architecture '\(hostArchitecture)', and target triple '\(targetTriple)'
            """
        case .cannotGetCompilerVersionStringFromNonAndroidSDK(let sdk):
          return """
            Swift Bundler doesn't support fetching compiler version strings \
            from non-Android SDKs; sdk=\(sdk.generallyUniqueIdentifier)
            """
        case .couldNotLocateCompilerVersionString(let sdk, let interface):
          return """
            Could not detect Swift compiler version used to generate Swift \
            interface at '\(interface.path)' (in \
            '\(sdk.generallyUniqueIdentifier)' sdk)
            """
      }
    }
  }
}
