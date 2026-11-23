import ArgumentParser
import Foundation

/// The subcommand for managing and listing available devices.
struct DeviceCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "device",
    abstract: "Manage and list available devices.",
    subcommands: [
      DeviceListCommand.self,
      // Deprecated aliases
      DeprecatedDeviceListCommand.self
    ]
  )
}
