import ArgumentParser
import Foundation

/// A deprecated and hidden copy of the 'swift bundler config migrate' subcommand.
struct MigrateCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "migrate",
    abstract: """
      Deprecated version of 'swift bundler config migrate' provided for backwards \
      compatibility.
      """,
    shouldDisplay: false
  )

  @OptionGroup
  var wrappedCommand: ConfigMigrateCommand

  func validate() throws {
    log.warning(
      """
      'swift bundler migrate' has been deprecated; please use 'swift bundler \
      config migrate' instead
      """
    )
    print()
    wrappedCommand.validate()
  }

  func run() async throws {
    await wrappedCommand.run()
  }
}
