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
    transform: URL.init(fileURLWithPath:))
  var packageDirectory: URL?

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages.")
  public var verbose = false

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    _ = try await RichError<SwiftBundlerError>.catch {
      try await PackageConfiguration.load(
        fromDirectory: packageDirectory ?? URL(fileURLWithPath: "."),
        migrateConfiguration: true
      )
    }

    log.info("Successfully migrated configuration to the latest format.")
  }
}
