import Foundation
import TOMLKit
import ErrorKit
import Version

extension PackageConfiguration {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``PackageConfiguration``.
  enum ErrorMessage: Throwable {
    case noSuchApp(String)
    case noApps
    case multipleAppsAndNoneSpecified
    case failedToEvaluateVariables
    case failedToReadConfigurationFile(URL)
    case failedToDeserializeConfiguration
    case failedToSerializeConfiguration
    case failedToWriteToConfigurationFile(URL)
    case failedToReadContentsOfOldConfigurationFile(URL)
    case failedToDeserializeOldConfiguration
    case failedToCreateConfigurationBackup
    case failedToDeserializeV2Configuration
    case unsupportedFormatVersion(Int)
    case configurationIsAlreadyUpToDate
    case invalidFormatVersion(any TOMLValueConvertible & Sendable)
    case invalidCompatibility(any TOMLValueConvertible & Sendable)
    case compatibilityTooLow(Version)
    case unsupportedConfigCompatibility(Version)

    var userFriendlyMessage: String {
      switch self {
        case .noSuchApp(let name):
          return "This package doesn't contain an app called '\(name)'"
        case .noApps:
          return "This package doesn't contain any apps"
        case .multipleAppsAndNoneSpecified:
          return "This package contains multiple apps. You must provide the 'app-name' argument"
        case .failedToEvaluateVariables:
          return "Failed to evaluate all expressions"
        case .failedToReadConfigurationFile(let file):
          return
            "Failed to read the configuration file at '\(file.relativePath)'. Are you sure that it exists?"
        case .failedToDeserializeConfiguration:
          return "Failed to deserialize configuration"
        case .failedToSerializeConfiguration:
          return "Failed to serialize configuration"
        case .failedToWriteToConfigurationFile(let file):
          return "Failed to write to configuration file at '\(file.relativePath)"
        case .failedToDeserializeOldConfiguration:
          return "Failed to deserialize old configuration"
        case .failedToReadContentsOfOldConfigurationFile(let file):
          return "Failed to read contents of old configuration file at '\(file.relativePath)'"
        case .failedToCreateConfigurationBackup:
          return "Failed to backup configuration file"
        case .failedToDeserializeV2Configuration:
          return "Failed to deserialize configuration for migration"
        case .unsupportedFormatVersion(let formatVersion):
          return
            "Package configuration file has an invalid format version '\(formatVersion)' and could not"
            + " be automatically migrated. The latest format version is '\(PackageConfiguration.currentFormatVersion)'"
        case .configurationIsAlreadyUpToDate:
          return "Configuration file is already up-to-date"
        case .invalidFormatVersion(let formatVersion):
          return "Invalid format_version; got '\(formatVersion)', expected an integer"
        case .invalidCompatibility(let compatibility):
          return """
            Invalid compatibility; got '\(compatibility)', expected a semantic \
            version (encoded as a string)
            """
        case .compatibilityTooLow(let compatibility):
          let compat = PackageConfiguration.minimumCompatibilityVersion
          if SwiftBundler.version < compat {
            return """
              The compatibility field will be enabled in \(compat), so a \
              compatibility of \(compatibility) is not allowed; omit the \
              compatibility field in favor of the format_version field to support \
              Swift Bundler 3.0.0, or if Swift Bundler \(compat) has been released \
              increase your compatibility to at least \(compat) and update your Swift \
              Bundler installation
              """
          } else {
            return """
              The compatibility field was introduced in \(compat), so a \
              compatibility of \(compatibility) is not allowed; either \
              bump your compatibility to at least \(compat), or omit the \
              compatibility field in favor of the old format_version field to \
              support Swift Bundler 3.0.0 (which uses a format_version of \
              \(PackageConfiguration.currentFormatVersion))
              """
          }
        case .unsupportedConfigCompatibility(let compatibility):
          return """
            The target project states a compatibility of \(compatibility); update \
            your Swift Bundler CLI to at least version \(compatibility) to work \
            with this project
            """
      }
    }
  }
}
