import ArgumentParser
import Foundation

/// The subcommand for operations specific to simulators managed by simctl.
struct SimulatorSimctlCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "simctl",
    abstract: "Operations specific to simulators managed by simctl.",
    subcommands: [
      SimulatorSimctlBootCommand.self,
    ],
  )
}
