import ArgumentParser
import Foundation

/// The subcommand for booting simulators.
struct SimulatorsBootCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "boot",
    abstract: "Boot an iOS, tvOS, visionOS, or Android simulator."
  )

  /// The id or name of the simulator to start.
  @Argument(
    help: """
      The id or name of the simulator to start. Supports partial substring \
      matching.
      """)
  var idOrName: String

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages.")
  public var verbose = false

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    let simulator = try await RichError<SwiftBundlerError>.catch {
      try await SimulatorManager.locateSimulator(searchTerm: idOrName)
    }

    if simulator.id != simulator.name {
      log.info("Booting '\(simulator.name)' (id: \(simulator.id))")
    } else {
      log.info("Booting '\(simulator.name)'")
    }

    try await RichError<SwiftBundlerError>.catch {
      try await SimulatorManager.bootSimulator(simulator)
    }
  }
}
