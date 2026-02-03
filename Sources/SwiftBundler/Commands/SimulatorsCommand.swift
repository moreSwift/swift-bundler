import ArgumentParser
import Foundation

/// The subcommand for managing and listing available simulators.
struct SimulatorsCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "simulators",
    abstract: "Manage and list available iOS, tvOS and visionOS simulators.",
    subcommands: [
      SimulatorsListCommand.self,
      SimulatorsBootCommand.self,
    ],
    defaultSubcommand: SimulatorsListCommand.self
  )
}
