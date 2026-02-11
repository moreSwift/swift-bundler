import ArgumentParser
import Foundation

/// The subcommand for listing available simulators.
struct SimulatorsListCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "list",
    abstract: "List available iOS, tvOS, visionOS, and Android simulators."
  )

  @Option(
    help: "A search term to filter simulators with.")
  var filter: String?

  @Option(
    name: .customLong("os"),
    help: "Only show simulators for a specific OS.",
    transform: { osString in
      guard let os = SimulatorOS(rawValue: osString) else {
        throw SwiftBundlerError.invalidSimulatorOS(osString)
      }

      return os
    })
  public var oses: [SimulatorOS] = []

  @Flag(
    name: .customLong("booted"),
    help: "Only show booted simulators.")
  public var filterBooted = false

  @Flag(
    name: .customLong("not-booted"),
    help: "Only show simulators that aren't booted.")
  public var filterNotBooted = false

  @Flag(
    name: .customLong("apple"),
    help: "Only show Apple device simulators.")
  public var filterApple = false

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages.")
  public var verbose = false

  func wrappedValidate() throws(RichError<SwiftBundlerError>) {
    if filterApple && !oses.isEmpty {
      // This is a useless thing to do, so we make them explicitly mutually exclusive
      // in case gets themself into a confusing situation (e.g. where --filter-apple
      // and --os are both used in an existing command, and then they remove
      // --filter-apple expecting Android devices to show up)
      throw RichError(.commandLineValidationError(
        "'--filter-apple' and '--os' cannot be used together"
      ))
    }

    if filterBooted && filterNotBooted {
      throw RichError(.commandLineValidationError(
        "'--booted' and '--not-booted' cannot be used together"
      ))
    }
  }

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    var oses = oses.isEmpty ? SimulatorOS.allCases : oses
    if filterApple {
      oses = oses.filter(\.isAppleOS)
    }

    let simulators = try await RichError<SwiftBundlerError>.catch {
      try await SimulatorManager.listSimulators(oses: oses, searchTerm: filter)
    }

    let filteredSimulators = simulators.filter { simulator in
      if filterBooted && !simulator.isBooted {
        false
      } else if filterNotBooted && simulator.isBooted {
        false
      } else {
        true
      }
    }

    let filteredAppleSimulators = filteredSimulators.filter { $0.os.isAppleOS }
    let filteredAndroidSimulators = filteredSimulators.filter { $0.os == .android }

    Output {
      if oses.contains(where: { $0.isAppleOS }) {
        Section("Apple simulators (iOS, tvOS, visionOS)") {
          if filteredAppleSimulators.isEmpty {
            "None found".italic
          } else {
            KeyedList {
              for simulator in filteredAppleSimulators {
                KeyedList.Entry(
                  simulator.id,
                  "\(simulator.name) (\(simulator.os.displayName.bold), booted: \(simulator.isBooted))"
                )
              }
            }
          }
        }
      }

      if oses.contains(.android) {
        Section("Android simulators") {
          if filteredAndroidSimulators.isEmpty {
            "None found".italic
          } else {
            List {
              for simulator in filteredAndroidSimulators {
                List.Entry("\(simulator.name) (booted: \(simulator.isBooted))")
              }
            }
          }
        }
      }
      
      Section("Booting a simulator") {
        ExampleCommand("swift bundler simulators boot [id-or-name]")
      }
    }.show()
  }
}
