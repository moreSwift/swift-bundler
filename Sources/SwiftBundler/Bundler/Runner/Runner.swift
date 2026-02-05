import Foundation

#if canImport(AppKit)
  import AppKit
#endif

/// A utility for running apps.
enum Runner {
  /// Runs the given app.
  /// - Parameters:
  ///   - bundlerOutput: The output of the bundler.
  ///   - bundleIdentifier: The app's bundle identifier.
  ///   - device: The device to run the app on.
  ///   - arguments: Command line arguments to pass to the app.
  ///   - environmentVariables: Environment variables to pass to the app.
  static func run(
    bundlerOutput: BundlerOutputStructure,
    bundleIdentifier: String,
    device: Device,
    arguments: [String] = [],
    environmentVariables: [String: String]
  ) async throws(Error) {
    // TODO: Test `arguments` on an actual iOS when I get the chance
    log.info("Running '\(bundlerOutput.bundle.lastPathComponent)'")

    switch device {
      case .host(let platform):
        guard let bundlerOutput = RunnableBundlerOutputStructure(bundlerOutput) else {
          throw Error(.missingExecutable(device, bundlerOutput))
        }

        switch platform {
          case .macOS:
            try await runMacOSAppOnHost(
              bundlerOutput: bundlerOutput,
              arguments: arguments,
              environmentVariables: environmentVariables
            )
          case .linux:
            try await runLinuxAppOnHost(
              bundlerOutput: bundlerOutput,
              arguments: arguments,
              environmentVariables: environmentVariables
            )
          case .windows:
            try await runWindowsAppOnHost(
              bundlerOutput: bundlerOutput,
              arguments: arguments,
              environmentVariables: environmentVariables
            )
        }
      case .macCatalyst:
        guard let bundlerOutput = RunnableBundlerOutputStructure(bundlerOutput) else {
          throw Error(.missingExecutable(device, bundlerOutput))
        }

        try await runMacOSAppOnHost(
          bundlerOutput: bundlerOutput,
          arguments: arguments,
          environmentVariables: environmentVariables
        )
      case .connectedAppleDevice(let connectedAppleDevice):
        try await runApp(
          on: connectedAppleDevice,
          bundlerOutput: bundlerOutput,
          bundleIdentifier: bundleIdentifier,
          arguments: arguments,
          environmentVariables: environmentVariables
        )
      case .connectedAndroidDevice(let connectedAndroidDevice):
        try await runApp(
          on: connectedAndroidDevice,
          bundlerOutput: bundlerOutput,
          bundleIdentifier: bundleIdentifier,
          arguments: arguments,
          environmentVariables: environmentVariables
        )
    }
  }

  /// Loads a set of environment variables from an environment file.
  /// - Parameter environmentFile: A file containing lines of the form 'key=value'.
  /// - Returns: A dictionary containing the environment variables.
  static func loadEnvironmentVariables(
    from environmentFile: URL
  ) throws(Error) -> [String: String] {
    let contents: String
    do {
      contents = try String(contentsOf: environmentFile)
    } catch {
      throw Error(.failedToReadEnvironmentFile(environmentFile), cause: error)
    }

    let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
    var variables: [String: String] = [:]
    for line in lines {
      let parts = line.split(separator: "=", maxSplits: 1)
      guard let key = parts.first, let value = parts.last else {
        throw Error(.failedToParseEnvironmentFileEntry(line: String(line)))
      }
      variables[String(key)] = String(value)
    }

    return variables
  }

  /// Runs an app on the host device. Assumes that the host is a macOS
  /// machine.
  /// - Parameters:
  ///   - bundlerOutput: The output of the bundler.
  ///   - arguments: Command line arguments to pass to the app.
  ///   - environmentVariables: Environment variables to pass to the app.
  static func runMacOSAppOnHost(
    bundlerOutput: RunnableBundlerOutputStructure,
    arguments: [String],
    environmentVariables: [String: String]
  ) async throws(Error) {
    let executable = bundlerOutput.executable

    let process = Process.create(
      executable.path,
      runSilentlyWhenNotVerbose: false
    )
    process.arguments = arguments
    process.addEnvironmentVariables(environmentVariables)

    #if canImport(AppKit)
      // Bring the app to the foreground once launched.
      let center = NSWorkspace.shared.notificationCenter
      center.addObserver(
        forName: NSWorkspace.didLaunchApplicationNotification,
        object: nil,
        queue: OperationQueue.main
      ) { (notification: Notification) in
        guard
          let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication,
          app.bundleURL == bundlerOutput.bundle
        else {
          return
        }

        app.activate()
      }
    #endif

    try await Error.catch(withMessage: .failedToRunExecutable) {
      try await process.runAndWait()
    }
  }

  /// Runs a linux app on the host device. Assumes that the host is a Linux
  /// machine.
  /// - Parameters:
  ///   - bundlerOutput: The output of the bundler.
  ///   - arguments: Command line arguments to pass to the app.
  ///   - environmentVariables: Environment variables to pass to the app.
  static func runLinuxAppOnHost(
    bundlerOutput: RunnableBundlerOutputStructure,
    arguments: [String],
    environmentVariables: [String: String]
  ) async throws(Error) {
    // runAppImage is a workaround required to run certain app images, but it
    // works for regular executable too so we just use it in all cases.
    try await Error.catch(withMessage: .failedToRunExecutable) {
      try await Process.runAppImage(bundlerOutput.executable.path, arguments: arguments)
    }
  }

  /// Runs a Windows app on the host device. Assumes that the host is a Windows
  /// machine.
  /// - Parameters:
  ///   - bundlerOutput: The output of the bundler.
  ///   - arguments: Command line arguments to pass to the app.
  ///   - environmentVariables: Environment variables to pass to the app.
  static func runWindowsAppOnHost(
    bundlerOutput: RunnableBundlerOutputStructure,
    arguments: [String],
    environmentVariables: [String: String]
  ) async throws(Error) {
    try await Error.catch(withMessage: .failedToRunExecutable) {
      try await Process.create(
        bundlerOutput.executable.path,
        arguments: arguments,
        environment: environmentVariables
      ).runAndWait()
    }
  }

  /// Runs an app on a connected Apple device or Apple simulator.
  /// - Parameters:
  ///   - connectedDevice: The device/simulator to run the app on.
  ///   - bundlerOutput: The output of the bundler.
  ///   - bundleIdentifier: The app's bundle identifier.
  ///   - arguments: Command line arguments to pass to the app.
  ///   - environmentVariables: Environment variables to pass to the app.
  static func runApp(
    on connectedDevice: ConnectedAppleDevice,
    bundlerOutput: BundlerOutputStructure,
    bundleIdentifier: String,
    arguments: [String],
    environmentVariables: [String: String]
  ) async throws(Error) {
    if connectedDevice.platform.isSimulator {
      try await runAppOnSimulator(
        simulatorId: connectedDevice.id,
        bundlerOutput: bundlerOutput,
        bundleIdentifier: bundleIdentifier,
        arguments: arguments,
        environmentVariables: environmentVariables
      )
    } else {
      try await runAppOnPhysicalDevice(
        deviceId: connectedDevice.id,
        bundlerOutput: bundlerOutput,
        bundleIdentifier: bundleIdentifier,
        arguments: arguments,
        environmentVariables: environmentVariables
      )
    }
  }

  /// Runs an app on a connected Android device or Android emulator.
  /// - Parameters:
  ///   - connectedDevice: The device/simulator to run the app on.
  ///   - bundlerOutput: The output of the bundler.
  ///   - bundleIdentifier: The app's bundle identifier.
  ///   - arguments: Command line arguments to pass to the app.
  ///   - environmentVariables: Environment variables to pass to the app.
  static func runApp(
    on connectedDevice: ConnectedAndroidDevice,
    bundlerOutput: BundlerOutputStructure,
    bundleIdentifier: String,
    arguments: [String],
    environmentVariables: [String: String]
  ) async throws(Error) {
    fatalError("TODO")
  }

  static func runAppOnPhysicalDevice(
    deviceId: String,
    bundlerOutput: BundlerOutputStructure,
    bundleIdentifier: String,
    arguments: [String],
    environmentVariables: [String: String]
  ) async throws(Error) {
    let environmentArguments: [String]
    if !environmentVariables.isEmpty {
      // TODO: correctly escape keys and values
      let value = environmentVariables.map { key, value in
        return "\(key)=\(value)"
      }.joined(separator: " ")
      environmentArguments = ["--envs", "\(value)"]
    } else {
      environmentArguments = []
    }

    let output = try await Error.catch(withMessage: .failedToGetXcodeDeveloperDirectory) {
      try await Process.create("xcode-select", arguments: ["--print-path"])
        .getOutput()
    }

    let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
    let devicectlExecutable = URL(fileURLWithPath: path) / "usr/bin/devicectl"

    // ios-deploy doesn't work well with newer Xcode versions because Apple
    // made a few breaking changes. Luckily, Apple created the devicectl
    // tool at around the same time. If we detect devicectl, we use it
    // because it's more likely to work, otherwise we fall back to
    // ios-deploy.

    guard devicectlExecutable.exists() else {
      // Fall back to ios-deploy.
      // `ios-deploy` is explicitly resolved so that a detailed error
      // message can be emitted for this easy misconfiguration issue.
      let iosDeployExecutable = try await Error.catch(withMessage: .failedToLocateIOSDeploy) {
        try await Process.locate("ios-deploy")
      }

      try await Error.catch(withMessage: .failedToRunIOSDeploy) {
        try await Process.create(
          iosDeployExecutable,
          arguments: [
            "--noninteractive",
            "--bundle", bundlerOutput.bundle.path,
            "--id", deviceId,
          ] + environmentArguments
            + arguments.flatMap { argument in
              return ["--args", argument]
            },
          runSilentlyWhenNotVerbose: false
        ).runAndWait()
      }

      return
    }

    // Install and run with devicectl
    do {
      try await Process.create(
        devicectlExecutable.path,
        arguments: [
          "device", "install", "app",
          "--device", deviceId,
          bundlerOutput.bundle.path,
        ],
        runSilentlyWhenNotVerbose: false
      ).runAndWait()

      try await Process.create(
        devicectlExecutable.path,
        arguments: [
          "device", "process", "launch",
          "--device", deviceId,
          "--console",
          bundleIdentifier,
        ],
        runSilentlyWhenNotVerbose: false
      ).runAndWait()
    } catch {
      throw Error(.failedToRunAppOnConnectedDevice, cause: error)
    }
  }

  /// Runs an app on an Apple device simulator.
  /// - Parameters:
  ///   - simulatorId: The id of the simulator to run.
  ///   - bundlerOutput: The output of the bundler.
  ///   - bundleIdentifier: The app's identifier.
  ///   - arguments: Command line arguments to pass to the app.
  ///   - environmentVariables: Environment variables to pass to the app.
  static func runAppOnSimulator(
    simulatorId: String,
    bundlerOutput: BundlerOutputStructure,
    bundleIdentifier: String,
    arguments: [String],
    environmentVariables: [String: String]
  ) async throws(Error) {
    do {
      log.info("Preparing simulator")
      try await SimulatorManager.bootSimulator(id: simulatorId)

      log.info("Installing app")
      try await SimulatorManager.installApp(bundlerOutput.bundle, simulatorId: simulatorId)

      log.info("Opening Simulator")
      try await SimulatorManager.openSimulatorApp()

      log.info("Launching \(bundleIdentifier)")
      try await SimulatorManager.launchApp(
        bundleIdentifier,
        simulatorId: simulatorId,
        connectConsole: true,
        arguments: arguments,
        environmentVariables: environmentVariables
      )
    } catch {
      throw Error(.failedToRunOnSimulator, cause: error)
    }
  }
}
