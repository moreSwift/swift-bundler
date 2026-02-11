import ArgumentParser
import Foundation

/// The subcommand for managing and listing available simulators.
struct SimulatorsCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "simulators",
    abstract: "Manage and list available iOS, tvOS, visionOS, and Android simulators.",
    subcommands: [
      SimulatorsListCommand.self,
      SimulatorsBootCommand.self,
      SimulatorsSimctlCommand.self,
      SimulatorsAVDCommand.self,
    ],
    defaultSubcommand: SimulatorsListCommand.self
  )
}
