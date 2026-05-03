import Foundation
import ErrorKit

#if SUPPORT_XCODEPROJ
  @preconcurrency import XcodeProj
#endif

extension XcodeprojConverter {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``XcodeprojConverter``.
  enum ErrorMessage: Throwable {
    case hostPlatformNotSupported
    case failedToLoadXcodeProj(URL)
    case failedToEnumerateSources(target: String)
    case failedToCreateTargetDirectory(target: String, URL)
    case failedToCopyFile(source: URL, destination: URL)
    case failedToCreatePackageManifest(URL)
    case failedToCreateConfigurationFile(URL)
    case directoryAlreadyExists(URL)
    case failedToLoadXcodeWorkspace(URL)
    case failedToCreateAppConfiguration(target: String)

    #if SUPPORT_XCODEPROJ
      case unsupportedFilePathType(PBXSourceTree)
      case invalidBuildFile(PBXBuildFile)
      case failedToGetRelativePath(PBXFileElement)
    #endif

    var userFriendlyMessage: String {
      switch self {
        case .hostPlatformNotSupported:
          return """
            xcodeproj conversion isn't supported on \
            \(HostPlatform.hostPlatform.platform.name)
            """
        case .failedToLoadXcodeProj(let file):
          return "Failed to load xcodeproj from '\(file.relativePath)'"
        case .failedToEnumerateSources(let target):
          return "Failed to enumerate sources for target '\(target)'"
        case .failedToCreateTargetDirectory(let target, _):
          return "Failed to create directory for target '\(target)'"
        case .failedToCopyFile:
          return "Failed to copy file"
        case .failedToCreatePackageManifest(_):
          return "Failed to create package manifest"
        case .failedToCreateConfigurationFile(_):
          return "Failed to create configuration file"
        case .directoryAlreadyExists(let directory):
          return "Directory already exists at '\(directory.relativePath)'"
        case .failedToLoadXcodeWorkspace(let file):
          return "Failed to load xcworkspace from '\(file.relativePath)'"
        case .failedToCreateAppConfiguration(let target):
          return "Failed to create app configuration for '\(target)'"
        #if SUPPORT_XCODEPROJ
          case .unsupportedFilePathType(let pathType):
            return "Unsupported file path type '\(pathType.description)'"
          case .invalidBuildFile(let file):
            return "Encountered invalid build file with uuid '\(file.uuid)'"
          case .failedToGetRelativePath(let file):
            return "Failed to get relative path of '\(file.name ?? "unknown file")'"
        #endif
      }
    }
  }
}
