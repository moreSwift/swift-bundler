import Foundation
import ErrorKit

/// A top-level error thrown by the Swift Bundler.
enum SwiftBundlerError: Throwable {
  case invalidPlatform(String)
  case invalidArchitecture(String)
  case invalidBuildConfiguration(String)
  case invalidBundlerChoice(String)
  case failedToCopyIcon(source: URL, destination: URL)
  case failedToGetPlatformVersion(platform: Platform, manifest: URL)
  case failedToRemoveExistingOutputs(outputDirectory: URL)
  case invalidXcodeprojDetected
  case failedToResolveTargetDevice(reason: String)
  case failedToResolveCodeSigningConfiguration(reason: String)
  case failedToCopyOutBundle
  case missingConfigurationFile(URL)
  case codesigningNotSupported(HostPlatform)

  var userFriendlyMessage: String {
    switch self {
      case .invalidPlatform(let platform):
        return """
          Invalid platform '\(platform)'. Must be one of \
          \(Platform.possibleValuesDescription)
          """
      case .invalidArchitecture(let architecture):
        return """
          Invalid architecture '\(architecture)'. Must be one of \
          \(BuildArchitecture.possibleValuesDescription)
          """
      case .invalidBuildConfiguration(let buildConfiguration):
        return """
          Invalid build configuration '\(buildConfiguration)'. Must be one of \
          \(BuildConfiguration.possibleValuesDescription)
          """
      case .invalidBundlerChoice(let choice):
        return """
          Invalid bundler choice '\(choice)'. Must be one of \
          \(BundlerChoice.possibleValuesDescription)
          """
      case .failedToCopyIcon(let source, let destination):
        return "Failed to copy icon from '\(source)' to '\(destination)'"
      case .failedToGetPlatformVersion(let platform, let manifest):
        return """
          To build for \(platform.name) you must specify a minimum deployment \
          version for the relevant platform in the 'platforms' field of \
          '\(manifest.relativePath)'
          """
      case .failedToRemoveExistingOutputs(let outputDirectory):
        return """
          Failed to remove existing bundler outputs at \
          '\(outputDirectory.relativePath)'
          """
      case .invalidXcodeprojDetected:
        return """
          The --xcodebuild flag, which is the default flag when building any embedded Darwin \
          platforms such as iOS, visionOS, tvOS, and watchOS will not function correctly while \
          an xcodeproj or xcworkspace is in the same directory as your Package.swift. Please \
          remove any .xcodeproj and .xcworkspace directories listed above and try again. \

          If you cannot remove the xcodeproj or xcworkspace, you must stick to Swift Bundler's \
          default SwiftPM-based build system, you may pass the --no-xcodebuild flag to the bundler \
          to override embedded Darwin platforms such as iOS, visionOS, tvOS, and watchOS to use the \
          SwiftPM-based build system instead of the xcodebuild one.
          """
      case .failedToResolveTargetDevice(let reason):
        return "Failed to resolve target device: \(reason)"
      case .failedToResolveCodeSigningConfiguration(let reason):
        return "Failed to resolve code-signing configuration: \(reason)"
      case .failedToCopyOutBundle:
        return "Failed to copy out bundle"
      case .missingConfigurationFile(let file):
        return """
          Could not find \(file.lastPathComponent) at standard location. Are you \
          sure that you're in the root of a Swift Bundler project?
          """
      case .codesigningNotSupported(let platform):
        return """
          Code-signing isn't supported on \(platform.platform.displayName)
          """
    }
  }
}
