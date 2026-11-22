import ArgumentParser
import Foundation

/// The command for managing and listing signing identities.
struct IdentitiesCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "identities",
    abstract: "Manage and list available signing identities.",
    subcommands: [
      IdentitiesListCommand.self,
    ],
    defaultSubcommand: IdentitiesListCommand.self
  )
}
