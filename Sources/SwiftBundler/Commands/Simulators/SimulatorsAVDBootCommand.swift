import ArgumentParser
import Foundation

/// The subcommand for booting Android Virtual Devices.
struct SimulatorsAVDBootCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "boot",
    abstract: "Boot an Android Virtual Device."
  )

  @Argument(
    help: """
      The name of the emulator to start. Supports partial substring matching.
      """)
  var name: String

  @Argument(
    parsing: .postTerminator,
    help: "Additional arguments for the 'emulator' CLI.")
  var emulatorArguments: [String] = []

  @Option(
    name: .customLong("arch"),
    help: "Architecture to boot the emulator with.")
  var architecture: BuildArchitecture

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages.")
  public var verbose = false

  @Flag(
    name: .long,
    help: "Attach to 'emulator' CLI after booting the emulator.")
  var attach = false

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    let simulator = try await RichError<SwiftBundlerError>.catch {
      try await SimulatorManager.locateSimulator(
        oses: [.android],
        searchTerm: name
      )
    }

    try await RichError<SwiftBundlerError>.catch {
      log.info("Booting '\(simulator.name)'")
      try await AndroidVirtualDeviceManager.bootVirtualDevice(
        AndroidVirtualDevice(name: simulator.name),
        additionalArguments: emulatorArguments,
        detach: !attach
      )
    }
  }
}
