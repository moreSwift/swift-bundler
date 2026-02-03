import ArgumentParser
import Foundation

/// The subcommand for managing and listing available emulators.
struct EmulatorsCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "emulators",
    abstract: "Manage and list available Android emulators.",
    subcommands: [
      EmulatorsListCommand.self,
      EmulatorsBootCommand.self,
    ],
    defaultSubcommand: EmulatorsListCommand.self
  )
}
