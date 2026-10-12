import Foundation
import Parsing
import Version

/// The configuration for a CLI program.
@Configuration(overlayable: true)
struct CLIConfiguration: Codable, Hashable, Sendable {
  /// The cli's identifier (e.g. `com.example.cli`). Used when producing
  /// installers.
  var identifier: String

  /// The name of the executable product.
  var product: String

  /// The CLI's current version.
  var version: Version

  /// A short summary describing the purpose of the CLI.
  @ConfigurationKey("description")
  var cliDescription: String?

  /// The license type of the CLI.
  var license: String?

  /// A dictionary containing extra entries to add to the CLI's metadata (embedded in the
  /// main executable).
  ///
  /// String values can contain variable substitutions (see ``VariableEvaluator`` for details).
  var metadata: [String: MetadataValue]?

  /// Dependency identifiers of dependencies built by Swift Bundler before this
  /// build is invoked. Allows for integration with non-SwiftPM build tools, and
  /// CLIs pulling in helper executables.
  var dependencies: [AppConfiguration.Dependency]?

  /// MSI bundler related configuration properties.
  var msi: MSI?

  /// Android related configuration properties.
  var android: Android?

  /// Windows related configuration properties.
  var windows: Windows?

  /// RPM specific configuration properties.
  var rpm: RPM?
}

extension CLIConfiguration.Flat {
  var cliDescriptionOrDefault: String {
    cliDescription ?? "None"
  }

  var licenseOrDefault: String {
    license ?? "Unknown"
  }

  var androidMinSDKOrDefault: Int {
    android?.minSDK ?? AppConfiguration.Android.defaultMinSDK
  }
}
