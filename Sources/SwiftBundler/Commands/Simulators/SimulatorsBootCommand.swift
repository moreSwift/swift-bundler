import ArgumentParser
import Foundation

/// The subcommand for booting simulators.
struct SimulatorsBootCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "boot",
    abstract: "Boot an iOS, tvOS or visionOS simulator."
  )

  /// The id or name of the simulator to start.
  @Argument(
    help: "The id or name of the simulator to start.")
  var idOrName: String

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages.")
  public var verbose = false

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    try await RichError<SwiftBundlerError>.catch {
      log.info("Booting '\(idOrName)'")
      try await SimulatorManager.bootSimulator(id: idOrName)
      log.info("Opening 'Simulator.app'")
      try await SimulatorManager.openSimulatorApp()
    }
  }
}
