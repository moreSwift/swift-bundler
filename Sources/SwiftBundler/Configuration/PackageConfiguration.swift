import Foundation
import TOMLKit
import Version

/// The configuration for a package.
@Configuration(overlayable: false)
struct PackageConfiguration: Codable {
  /// The current configuration format version.
  static let currentFormatVersion = 2

  /// The file name for Swift Bundler configuration files.
  static let configurationFileName = "Bundler.toml"

  /// The configuration format version.
  var formatVersion: Int
  /// The configuration for each app in the package (packages can contain multiple apps). Maps app name to app configuration.
  var apps: [String: AppConfiguration]
  /// The configuration for each lib in the package. Maps library name to
  /// library configuration. Generally used when integrating libraries built
  /// with different build systems such as CMake.
  var projects: [String: ProjectConfiguration]?

  /// Creates a new package configuration.
  /// - Parameter apps: The package's apps.
  /// - Parameter projects: The package's subprojects.
  init(
    apps: [String: AppConfiguration] = [:],
    projects: [String: ProjectConfiguration]? = nil
  ) {
    formatVersion = Self.currentFormatVersion
    self.apps = apps
    self.projects = projects
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
    let configurationFile = customFile
      ?? standardConfigurationFileLocation(for: packageDirectory)

    // Migrate old configuration if no new configuration exists
    let shouldAttemptJSONMigration = customFile == nil
    if shouldAttemptJSONMigration {
      let oldConfigurationFile = packageDirectory / "Bundle.json"
      let configurationExists = configurationFile.exists(withType: .file)
      let oldConfigurationExists = oldConfigurationFile.exists(withType: .file)
      if oldConfigurationExists && !configurationExists {
        return try migrateV1Configuration(
          from: oldConfigurationFile,
          to: migrateConfiguration ? configurationFile : nil
        )
      }
    }

    let contents: String
    do {
      contents = try String(contentsOf: configurationFile)
    } catch {
      throw Error(.failedToReadConfigurationFile(configurationFile), cause: error)
    }

    let configuration: PackageConfiguration
    do {
      configuration = try Error.catch(withMessage: .failedToDeserializeConfiguration) {
        var decoder = TOMLDecoder(strictDecoding: true)
        // Tolerant version parsing
        decoder.userInfo[.decodingMethod] = DecodingMethod.tolerant
        return try decoder.decode(
          PackageConfiguration.self,
          from: contents
        )
      }

      if migrateConfiguration {
        throw Error(.configurationIsAlreadyUpToDate)
      }
    } catch {
      if case .configurationIsAlreadyUpToDate = (error as? Error)?.message {
        // TODO: See if full typed throws fixes this
        // swiftlint:disable:next force_cast
        throw error as! Error
      }

      // Maybe the configuration is a Swift Bundler v2 configuration.
      // Attempt to migrate it.
      let table = try Error.catch(withMessage: .failedToDeserializeConfiguration) {
        try TOMLTable(string: contents)
      }

      guard !table.contains(key: CodingKeys.formatVersion.rawValue) else {
        // TODO: See if full typed throws fixes this
        // swiftlint:disable:next force_cast
        throw error as! Error
      }

      return try await migrateV2Configuration(
        configurationFile,
        mode: migrateConfiguration ? .writeChanges(backup: true) : .readOnly
      )
    }

    guard configuration.formatVersion == PackageConfiguration.currentFormatVersion else {
      throw Error(.unsupportedFormatVersion(configuration.formatVersion))
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
  ///   - configurationFile: The configuration file to migrate.
  ///   - mode: The migration mode to use.
  /// - Returns: The migrated configuration.
  static func migrateV2Configuration(
    _ configurationFile: URL,
    mode: MigrationMode
  ) async throws(Error) -> PackageConfiguration {
    if mode == .readOnly {
      log.warning("'\(configurationFile.relativePath)' is outdated.")
      log.warning("Run 'swift bundler migrate' to migrate it to the latest config format.")
    }

    let contents: String
    do {
      contents = try String(contentsOf: configurationFile)
    } catch {
      throw Error(.failedToReadConfigurationFile(configurationFile), cause: error)
    }

    // Back up the file if requested.
    if mode == .writeChanges(backup: true) {
      let backupFile = configurationFile.appendingPathExtension("orig")
      try Error.catch(withMessage: .failedToCreateConfigurationBackup) {
        try contents.write(to: configurationFile)
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
      try writeConfiguration(configuration, to: configurationFile)
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
      log.warning("Use 'swift bundler migrate' to update your configuration to the latest format")
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
    directory.appendingPathComponent(configurationFileName)
  }
}

extension PackageConfiguration.Flat {
  /// Gets the configuration for the specified app. If no app is specified
  /// and there is only one app, that app is returned.
  /// - Parameter name: The name of the app to get.
  /// - Returns: The app's name and configuration.
  /// - Throws: If no app is specified, and there is more than one app.
  func getAppConfiguration(
    _ name: String?
  ) throws(PackageConfiguration.Error) -> (name: String, app: AppConfiguration.Flat) {
    if let name = name {
      guard let selected = apps[name] else {
        throw PackageConfiguration.Error(.noSuchApp(name))
      }
      return (name: name, app: selected)
    } else if let first = apps.first, apps.count == 1 {
      return (name: first.key, app: first.value)
    } else {
      throw PackageConfiguration.Error(.multipleAppsAndNoneSpecified)
    }
  }
}
