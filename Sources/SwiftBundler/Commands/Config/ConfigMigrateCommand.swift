import ArgumentParser
import Foundation

/// The command for migrating project config files to the latest format.
struct ConfigMigrateCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "migrate",
    abstract: "Migrate a project's config file to the latest format."
  )

  /// The directory containing the package to build.
  @Option(
    name: [.customShort("d"), .customLong("directory")],
    help: "The directory containing the package to migrate.",
    transform: URL.init(fileURLWithPath:)
  )
  var packageDirectory: URL?

  /// Overrides the default configuration file location.
  @Option(
    name: [.customLong("config-file")],
    help: "Overrides the default configuration file location",
    transform: URL.init(fileURLWithPath:)
  )
  var configurationFile: URL?

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages."
  )
  public var verbose = false

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    do {
      _ = try await PackageConfiguration.load(
        fromDirectory: packageDirectory ?? URL(fileURLWithPath: "."),
        customFile: configurationFile,
        migrateConfiguration: true
      )
    } catch let error {
      if case .configurationIsAlreadyUpToDate = error.message {
        log.info("Already up to date")
        return
      }
      throw RichError(cause: error)
    }

    log.info("Successfully migrated configuration to the latest format.")
  }
}
