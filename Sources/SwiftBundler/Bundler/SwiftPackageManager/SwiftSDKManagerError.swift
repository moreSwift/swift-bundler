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
      }
    }
  }
}
