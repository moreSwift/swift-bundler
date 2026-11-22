import ArgumentParser
import Foundation

/// A deprecated and hidden copy of the 'swift bundler identities list' subcommand.
struct ListIdentitiesCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "list-identities",
    abstract: """
      Deprecated version of 'swift bundler identities list' provided for backwards \
      compatibility.
      """,
    shouldDisplay: false
  )

  @OptionGroup
  var wrappedCommand: IdentitiesListCommand

  func validate() throws {
    log.warning(
      """
      'swift bundler list-identities' has been deprecated; please use 'swift bundler \
      identities list' instead
      """
    )
    print()
    wrappedCommand.validate()
  }

  func run() async throws {
    await wrappedCommand.run()
  }
}
