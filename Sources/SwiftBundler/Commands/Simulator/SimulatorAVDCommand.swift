import ArgumentParser
import Foundation

/// The subcommand for operations specific to Android Virtual Devices.
struct SimulatorAVDCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "avd",
    abstract: "Operations specific to Android Virtual Devices.",
    subcommands: [
      SimulatorAVDBootCommand.self,
    ],
  )
}
