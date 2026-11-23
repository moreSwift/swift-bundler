import ArgumentParser
import Foundation

/// The command for managing and listing signing identities.
struct IdentityCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "identity",
    abstract: "Manage and list available signing identities.",
    subcommands: [
      IdentityListCommand.self,
    ]
  )
}
