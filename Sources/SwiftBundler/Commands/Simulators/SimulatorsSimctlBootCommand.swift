import ArgumentParser
import Foundation

/// The subcommand for booting simulators.
struct SimulatorsSimctlBootCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "boot",
    abstract: "Boot an iOS, tvOS, visionOS, or Android simulator."
  )

  /// The id or name of the simulator to start.
  @Argument(
    help: """
      The id or name of the simulator to start. Substring matching is used \
      when filtering simulator names.
      """)
  var idOrName: String

  @Argument(
    parsing: .postTerminator,
    help: "Additional arguments to pass through to simctl.")
  var simctlArguments: [String] = []

  @Option(
    name: .customLong("arch"),
    help: "Architecture for the simulator.")
  var architecture: BuildArchitecture?

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages.")
  public var verbose = false

  func wrappedValidate() throws(RichError<SwiftBundlerError>) {
    if let architecture, ![.arm64, .x86_64].contains(architecture) {
      throw RichError(.commandLineValidationError(
        "Architecture \(architecture) is not supported for Apple simulators"
      ))
    }
  }

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    let simulator = try await RichError<SwiftBundlerError>.catch {
      try await SimulatorManager.locateSimulator(
        oses: SimulatorOS.allCases.filter(\.isAppleOS),
        searchTerm: idOrName
      )
    }

    log.info("Booting '\(simulator.name)' (id: \(simulator.id))")

    try await RichError<SwiftBundlerError>.catch {
      try await AppleSimulatorManager.bootSimulator(
        id: simulator.id,
        architecture: architecture,
        additionalArguments: simctlArguments
      )
    }
  }
}
