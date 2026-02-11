import Foundation

/// A utility for managing Apple simulators.
enum AppleSimulatorManager {
  /// Lists available simulators.
  /// - Parameter searchTerm: If provided, the simulators will be filtered using
  ///   the search term.
  /// - Returns: A list of available simulators matching the search term (if
  ///   provided), or a failure if an error occurs.
  static func listAvailableSimulators(
    searchTerm: String? = nil
  ) async throws(Error) -> [Simulator] {
    let data = try await Error.catch(withMessage: .failedToRunSimCTL) {
      try await Process.create(
        "/usr/bin/xcrun",
        arguments: [
          "simctl", "list", "devices",
          searchTerm, "available", "--json",
        ].compactMap { $0 }
      ).getOutputData(excludeStdError: true)
    }

    let simulatorList = try Error.catch(withMessage: .failedToDecodeJSON) {
      try JSONDecoder().decode(SimulatorList.self, from: data)
    }

    return simulatorList.devices
      .compactMap { (platform, platformSimulators) -> [Simulator]? in
        guard
          let os = NonMacAppleOS.allCases.first(where: { osCandidate in
            platform.hasPrefix(osCandidate.simulatorRuntimePrefix)
          })
        else {
          return nil
        }

        return platformSimulators.map { simulator in
          Simulator(
            id: simulator.id,
            name: simulator.name,
            isAvailable: simulator.isAvailable,
            isBooted: simulator.state == .booted,
            os: .apple(os)
          )
        }
      }
      .flatMap { $0 }
  }

  /// Boots a simulator. If it's already running, nothing is done.
  /// - Parameter id: The name or id of the simulator to start.
  static func bootSimulator(
    id: String,
    architecture: BuildArchitecture? = nil,
    additionalArguments: [String]? = nil
  ) async throws(Error) {
    var arguments = ["simctl", "boot", id]
    if let architecture {
      arguments += ["--arch=\(architecture.rawValue)"]
    }
    if let additionalArguments {
      arguments += additionalArguments
    }

    do {
      // We use getOutputData to access the data on error
      _ = try await Process.create(
        "/usr/bin/xcrun",
        arguments: arguments
      ).getOutputData()
    } catch {
      // If the device is already booted, count it as a success
      guard
        case let .nonZeroExitStatusWithOutput(data, _, _) = error.message,
        let output = String(data: data, encoding: .utf8),
        output.hasSuffix("Unable to boot device in current state: Booted\n")
      else {
        throw Error(.failedToRunSimCTL, cause: error)
      }
    }
  }

  /// Launches an app on the simulator (the app must already be installed).
  /// - Parameters:
  ///   - bundleIdentifier: The app's bundle identifier.
  ///   - simulatorId: The name or id of the simulator to launch in.
  ///   - connectConsole: If `true`, the function will block and the current
  ///     process will print the stdout and stderr of the running app.
  ///   - arguments: Command line arguments to pass to the app.
  ///   - environmentVariables: Additional environment variables to pass to the
  ///     app.
  static func launchApp(
    _ bundleIdentifier: String,
    simulatorId: String,
    connectConsole: Bool,
    arguments: [String],
    environmentVariables: [String: String]
  ) async throws(Error) {
    let process = Process.create(
      "/usr/bin/xcrun",
      arguments: [
        "simctl", "launch", connectConsole ? "--console-pty" : nil,
        simulatorId, bundleIdentifier,
      ].compactMap { $0 } + arguments,
      runSilentlyWhenNotVerbose: false
    )

    // TODO: Ensure that environment variables are passed correctly
    var prefixedVariables: [String: String] = [:]
    for (key, value) in environmentVariables {
      prefixedVariables["SIMCTL_CHILD_" + key] = value
    }

    process.addEnvironmentVariables(prefixedVariables)

    try await Error.catch(withMessage: .failedToRunSimCTL) {
      try await process.runAndWait()
    }
  }

  /// Installs an app on the simulator.
  /// - Parameters:
  ///   - bundle: The app bundle to install.
  ///   - simulatorId: The name or id of the simulator to install on.
  /// - Returns: A failure if an error occurs.
  static func installApp(
    _ bundle: URL,
    simulatorId: String
  ) async throws(Error) {
    try await Error.catch(withMessage: .failedToRunSimCTL) {
      try await Process.create(
        "/usr/bin/xcrun",
        arguments: [
          "simctl", "install", simulatorId, bundle.path,
        ]
      ).runAndWait()
    }
  }

  /// Opens the latest booted simulator in the simulator app.
  /// - Returns: A failure if an error occurs.
  static func openSimulatorApp() async throws(Error) {
    try await Error.catch(withMessage: .failedToOpenSimulator) {
      try await Process.create(
        "/usr/bin/open",
        arguments: [
          "-a", "Simulator",
        ]
      ).runAndWait()
    }
  }
}
