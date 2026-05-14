import Foundation
import TOMLKit
import Version

/// The configuration for a package.
@Configuration(overlayable: false)
struct PackageConfiguration: Codable, Hashable, Sendable {
  /// The current configuration format version.
  static let currentFormatVersion = 2

  /// The lower bound for the ``compatibility`` field. This doesn't mean that
  /// Swift Bundler doesn't support older configuration file formats (it still
  /// does), just that the ``compatibility`` field doesn't make sense for config
  /// files that are to be parsed by Swift Bundler versions before 3.1.0 (which
  /// is when we plan to enable the 'compatibility' field; enabling it sooner
  /// would lead to confusion when a file states 3.0.0 compatibility and a CLI
  /// that outputs its version as 3.0.0 fails to parse it, due to being a build
  /// from before the official 3.0.0 release).
  static let minimumCompatibilityVersion = Version(3, 1, 0)

  /// The file name for Swift Bundler configuration files.
  static let configurationFileName = "Bundler.toml"

  /// The configuration format version.
  var formatVersion: Int?

  /// The configuration file's Swift Bundler compatibility. In 4.0.0 this field
  /// will replace ``formatVersion``. We will support it from 3.1.0 to ease the
  /// transition to 4.0.0, and we will at the very least 'understand' the field
  /// in 3.0.0 to throw sensible errors (for users with new enough 3.0.0 builds
  /// that contain this code).
  var compatibility: Version?

  /// The configuration for each app in the package (packages can contain
  /// multiple apps). Maps app name to app configuration.
  var apps: [String: AppConfiguration]?

  /// The configuration for each project in the package. Maps project name to
  /// project configuration. Generally used when integrating libraries built
  /// with different build systems such as CMake.
  var projects: [String: ProjectConfiguration]?

  /// The configuration for each project builder defined within this package.
  /// Maps builder name to builder configuration.
  var builders: [String: BuilderConfiguration]?

  /// Optional configuration for each target in the package. Maps target name
  /// to target configuration.
  var targets: [String: TargetConfiguration]?

  /// Optional configuration for each product in the package. Maps product name
  /// to product configuration.
  var products: [String: ProductConfiguration]?

  /// Creates a new package configuration.
  /// - Parameters
  ///   - apps: The package's apps.
  ///   - projects: The package's subprojects.
  ///   - builders: The package's project builders.
  ///   - targets: The package's optional target configuration.
  ///   - products: The package's optional product configuration.
  init(
    apps: [String: AppConfiguration]? = nil,
    projects: [String: ProjectConfiguration]? = nil,
    builders: [String: BuilderConfiguration]? = nil,
    targets: [String: TargetConfiguration]? = nil,
    products: [String: ProductConfiguration]? = nil
  ) {
    formatVersion = Self.currentFormatVersion
    self.apps = apps
    self.projects = projects
    self.builders = builders
    self.targets = targets
    self.products = products
  }

  // MARK: Static methods

  /// Loads configuration from the `Bundler.toml` file in the given directory. Attempts to migrate outdated configurations.
  /// - Parameters:
  ///   - packageDirectory: The directory containing the configuration file.
  ///   - customFile: A custom configuration file not at the standard location.
  ///   - migrateConfiguration: If `true`, configuration is written to disk if the file is an old
  ///     configuration file and an error is thrown if the configuration is already at the latest
  ///     version.
  /// - Returns: The configuration.
  static func load(
    fromDirectory packageDirectory: URL,
    customFile: URL? = nil,
    migrateConfiguration: Bool = false
  ) async throws(Error) -> PackageConfiguration {
    let standardConfigurationFile = standardConfigurationFileLocation(for: packageDirectory)

    // Migrate old JSON configuration file if no new configuration exists
    let shouldAttemptJSONMigration = customFile == nil || customFile?.pathExtension == "json"
    if shouldAttemptJSONMigration {
      let oldConfigurationFile = customFile ?? packageDirectory / "Bundle.json"
      let configurationExists = standardConfigurationFile.exists(withType: .file)
      let oldConfigurationExists = oldConfigurationFile.exists(withType: .file)
      if oldConfigurationExists && !configurationExists {
        return try migrateV1Configuration(
          from: oldConfigurationFile,
          to: migrateConfiguration ? standardConfigurationFile : nil
        )
      }
    }

    let configurationFile = customFile ?? standardConfigurationFile
    let contents: String
    do {
      contents = try String(contentsOf: configurationFile)
    } catch {
      throw Error(.failedToReadConfigurationFile(configurationFile), cause: error)
    }

    return try await loadTOMLConfiguration(
      configurationFile,
      contents: contents,
      fromDirectory: packageDirectory,
      migrateConfiguration: migrateConfiguration
    )
  }

  static func loadTOMLConfiguration(
    _ location: URL,
    contents: String,
    fromDirectory packageDirectory: URL,
    migrateConfiguration: Bool
  ) async throws(Error) -> PackageConfiguration {
    let table = try Error.catch {
      try TOMLTable(string: contents)
    }

    let formatVersion: Int?
    if let formatVersionValue = table[CodingKeys.formatVersion.rawValue] {
      guard let formatVersionInt = formatVersionValue.int else {
        throw Error(.invalidFormatVersion(formatVersionValue))
      }

      // For a month or so, the format_version was bumped to version 3. We now
      // consider both format versions to be equivalent even though format version
      // 3 contained some additive, because treating them as separate (and generating
      // new Bundler.toml files with a format_version of 3), causes pre-release
      // Swift Bundler 3.0.0 builds to spit out cryptic errors (due to Swift Bundler
      // previously not checking the format_version field properly...)
      guard formatVersionInt == 2 || formatVersionInt == 3 else {
        throw Error(.unsupportedFormatVersion(formatVersionInt))
      }

      formatVersion = formatVersionInt
    } else {
      formatVersion = nil
    }

    let compatibility: Version?
    if let compatibilityValue = table[CodingKeys.compatibility.rawValue] {
      guard
        let compatibilityString = compatibilityValue.string,
        let compatibilityVersion = Version(compatibilityString)
      else {
        throw Error(.invalidCompatibility(compatibilityValue))
      }

      guard compatibilityVersion >= Self.minimumCompatibilityVersion else {
        throw Error(.compatibilityTooLow(compatibilityVersion))
      }

      guard compatibilityVersion <= SwiftBundler.version else {
        throw Error(.unsupportedConfigCompatibility(compatibilityVersion))
      }

      compatibility = compatibilityVersion
    } else {
      compatibility = nil
    }

    // If we're missing the format_version or compatibility fields then we
    // assume we're working with a Swift Bundler 2.x configuration (not to
    // be confused with a 'format_version = 2' configuration...)
    let configuration: PackageConfiguration
    if formatVersion == nil && compatibility == nil {
      configuration = try await migrateV2Configuration(
        location,
        contents: contents,
        mode: migrateConfiguration ? .writeChanges(backup: true) : .readOnly
      )
    } else {
      // Parse the config file as a post-v2 configuration
      configuration = try Error.catch(withMessage: .failedToDeserializeConfiguration) {
        var decoder = TOMLDecoder(strictDecoding: true)
        // Tolerant version parsing
        decoder.userInfo[.decodingMethod] = DecodingMethod.tolerant
        return try decoder.decode(
          PackageConfiguration.self,
          from: table
        )
      }

      if migrateConfiguration {
        throw Error(.configurationIsAlreadyUpToDate)
      }
    }

    return try await Error.catch(withMessage: .failedToEvaluateVariables) {
      try await VariableEvaluator.evaluateVariables(
        in: configuration,
        packageDirectory: packageDirectory
      )
    }
  }

  /// Migrates a Swift Bundler `v2.0.0` configuration file to the current configuration format.
  ///
  /// Mutates the contents of the given configuration file.
  /// - Parameters:
  ///   - location: The configuration file to migrate.
  ///   - contents: The contents of the configuration file.
  ///   - mode: The migration mode to use.
  /// - Returns: The migrated configuration.
  static func migrateV2Configuration(
    _ location: URL,
    contents: String,
    mode: MigrationMode
  ) async throws(Error) -> PackageConfiguration {
    if mode == .readOnly {
      log.warning("'\(location.relativePath)' is outdated.")
      log.warning(
        "Run 'swift bundler config migrate' to migrate it to the latest config format."
      )
    }

    // Back up the file if requested.
    if mode == .writeChanges(backup: true) {
      let backupFile = location.appendingPathExtension("orig")
      try Error.catch(withMessage: .failedToCreateConfigurationBackup) {
        try contents.write(to: location)
      }

      log.info(
        """
        The original configuration has been backed up to \
        '\(backupFile.relativePath)'
        """
      )
    }

    // Decode the old configuration
    let oldConfiguration = try Error.catch(withMessage: .failedToDeserializeV2Configuration) {
      try TOMLDecoder().decode(PackageConfigurationV2.self, from: contents)
    }

    // Migrate the configuration
    let configuration = await oldConfiguration.migrate()

    // Write the changes if requested
    if case .writeChanges = mode {
      log.info("Writing migrated config to disk.")
      try writeConfiguration(configuration, to: location)
    }

    return configuration
  }

  /// Migrates a `Bundle.json` to a `Bundler.toml` file.
  /// - Parameters:
  ///   - oldConfigurationFile: The `Bundle.json` file to migrate.
  ///   - newConfigurationFile: The `Bundler.toml` file to output to. If `nil` the migrated
  ///     configuration is not written to disk.
  /// - Returns: The converted configuration.
  static func migrateV1Configuration(
    from oldConfigurationFile: URL,
    to newConfigurationFile: URL?
  ) throws(Error) -> PackageConfiguration {
    log.warning("No 'Bundler.toml' file was found, but a 'Bundle.json' file was")
    if newConfigurationFile == nil {
      log.warning(
        "Use 'swift bundler config migrate' to update your configuration to the latest format"
      )
    } else {
      log.info("Migrating 'Bundle.json' to the new configuration format")
    }

    let oldConfiguration = try PackageConfigurationV1.load(
      from: oldConfigurationFile
    )
    let newConfiguration = oldConfiguration.migrate()

    if let newConfigurationFile {
      try writeConfiguration(newConfiguration, to: newConfigurationFile)

      log.info(
        """
        Only the 'product' and 'version' fields are mandatory. You can \
        delete any others that you don't need
        """
      )
      log.info(
        """
        'Bundle.json' was successfully migrated to 'Bundler.toml', you can \
        now safely delete it
        """
      )
    }

    return newConfiguration
  }

  /// Writes the given configuration to the given file.
  static func writeConfiguration(
    _ configuration: PackageConfiguration,
    to file: URL
  ) throws(Error) {
    let newContents = try Error.catch(withMessage: .failedToSerializeConfiguration) {
      try TOMLEncoder().encode(configuration)
    }

    do {
      try newContents.write(to: file)
    } catch {
      throw Error(.failedToWriteToConfigurationFile(file), cause: error)
    }
  }

  /// Gets the standard configuration file location for a given directory.
  static func standardConfigurationFileLocation(for directory: URL) -> URL {
    directory / configurationFileName
  }
}

extension PackageConfiguration.Flat {
  /// Gets the configuration for the specified app. If no app is specified
  /// and there is only one app, that app is returned.
  /// - Parameter name: The name of the app to get.
  /// - Returns: The app's name and configuration.
  /// - Throws: If no app is specified, and there is more than one app, or if
  ///   there are no apps.
  func getAppConfiguration(
    _ name: String?
  ) throws(PackageConfiguration.Error) -> (name: String, app: AppConfiguration.Flat) {
    if let name = name {
      guard let selected = apps[name] else {
        throw PackageConfiguration.Error(
          .noSuchApp(name),
          hint: Output {
            "Run `swift bundler config apps` to list available apps"
          }.description
        )
      }
      return (name: name, app: selected)
    } else if let first = apps.first, apps.count == 1 {
      return (name: first.key, app: first.value)
    } else if apps.count > 1 {
      throw PackageConfiguration.Error(.multipleAppsAndNoneSpecified)
    } else { // apps.count == 0
      throw PackageConfiguration.Error(.noApps)
    }
  }
}
