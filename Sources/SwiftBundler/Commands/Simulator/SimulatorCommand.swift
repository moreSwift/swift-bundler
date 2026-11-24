import ArgumentParser
import Foundation

/// The subcommand for managing and listing available simulators.
struct SimulatorCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "simulator",
    abstract: "Manage and list available iOS, tvOS, visionOS, and Android simulators.",
    subcommands: [
      SimulatorListCommand.self,
      SimulatorBootCommand.self,
      SimulatorSimctlCommand.self,
      SimulatorAVDCommand.self,
      // Deprecated commands
      DeprecatedSimulatorListCommand.self,
    ]
  )
}
