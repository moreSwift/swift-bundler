import Foundation
import ErrorKit

extension SwiftPackageManager {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``SwiftPackageManager``.
  enum ErrorMessage: Throwable {
    case failedToCreatePackageDirectory(URL)
    case failedToGetSwiftVersion
    case invalidSwiftVersionOutput(String)
    case failedToGetProductsDirectory
    case failedToGetLatestSDKPath(Platform)
    case failedToGetTargetInfo(command: String)
    case failedToParseTargetInfo(json: String)
    case failedToParsePackageManifestOutput(json: String)
    case failedToParsePackageManifestToolsVersion
    case failedToReadBuildPlan(path: URL)
    case failedToDecodeBuildPlan
    case failedToComputeLinkingCommand(details: String)
    case failedToRunModifiedLinkingCommand
    case missingDarwinPlatformVersion(Platform)
    case failedToGetToolsVersion
    case invalidToolsVersion(String)
    case cannotCompileExecutableAsDylibForPlatform(Platform)
    case cannotBuildForMultipleAndroidArchitecturesAtOnce
    case failedToReadArtifactBundleInfoJSON(URL)

    var userFriendlyMessage: String {
      switch self {
        case .failedToCreatePackageDirectory(let directory):
          return "Failed to create package directory at '\(directory.relativePath)'"
        case .failedToGetSwiftVersion:
          return "Failed to get Swift version"
        case .invalidSwiftVersionOutput(let output):
          return "The output of 'swift --version' could not be parsed: '\(output)'"
        case .failedToGetProductsDirectory:
          return "Failed to get products directory"
        case .failedToGetLatestSDKPath(let platform):
          return "Failed to get latest \(platform.rawValue) SDK path"
        case .failedToGetTargetInfo(let command):
          return "Failed to get target info via '\(command)'"
        case .failedToParseTargetInfo:
          return "Failed to parse Swift target info"
        case .failedToParsePackageManifestOutput:
          return "Failed to parse package manifest output"
        case .failedToParsePackageManifestToolsVersion:
          return "Failed to parse package manifest tools version"
        case .failedToReadBuildPlan(let path):
          let buildPlan = path.path(relativeTo: URL(fileURLWithPath: "."))
          return "Failed to read build plan file at '\(buildPlan)'"
        case .failedToDecodeBuildPlan:
          return "Failed to decode build plain"
        case .failedToComputeLinkingCommand(let details):
          return "Failed to compute linking command: \(details)"
        case .failedToRunModifiedLinkingCommand:
          return "Failed to run modified linking commmand"
        case .missingDarwinPlatformVersion(let platform):
          return """
            Missing target platform version for '\(platform.rawValue)' in \
            'Package.swift'. Please update the `Package.platforms` array \
            and try again. Building for Darwin platforms requires a target \
            platform.
            """
        case .failedToGetToolsVersion:
          return "Failed to get Swift package manifest tools version"
        case .invalidToolsVersion(let version):
          return "Invalid Swift tools version '\(version)' (expected a semantic version)"
        case .cannotCompileExecutableAsDylibForPlatform(let platform):
          return "Cannot compile executable as dylib for platform '\(platform)'"
        case .cannotBuildForMultipleAndroidArchitecturesAtOnce:
          return "Cannot build for multiple Android architectures at once"
        case .failedToReadArtifactBundleInfoJSON(let file):
          return "Failed to read artifactbundle's info.json at '\(file.path)'"
      }
    }
  }
}
