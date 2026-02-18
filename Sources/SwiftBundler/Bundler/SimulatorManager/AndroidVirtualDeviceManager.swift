import Foundation

/// A utility for interacting with the Android avdmanager CLI and emulator CLI,
/// responsible for managing and launching Android Virtual Devices.
enum AndroidVirtualDeviceManager {
  /// Locates the `avdmanager` executable.
  static func locateAVDManagerExecutable() throws(Error) -> URL {
    let sdk = try Error.catch(withMessage: .failedToLocateAVDManagerExecutable(nil)) {
      try AndroidSDKManager.locateAndroidSDK()
    }
    return try locateAVDManagerExecutable(inAndroidSDK: sdk)
  }

  /// Locates the `avdmanager` executable in the given Android SDK.
  static func locateAVDManagerExecutable(inAndroidSDK sdk: URL) throws(Error) -> URL {
    // There a few different copies of avdmanager in the Android SDK. This seems
    // to be the one that works best. Others fail when you have a Java version
    // newer than Java 8 installed... (at least on macOS)
    let executable = sdk / "cmdline-tools/latest/bin/avdmanager"
    guard executable.exists() else {
      throw Error(.failedToLocateAVDManagerExecutable(executable))
    }
    return executable
  }

  /// Locates the `emulator` command executable.
  static func locateEmulatorCommandExecutable() throws(Error) -> URL {
    let sdk = try Error.catch(withMessage: .failedToLocateEmulatorCommandExecutable(nil)) {
      try AndroidSDKManager.locateAndroidSDK()
    }
    return try locateEmulatorCommandExecutable(inAndroidSDK: sdk)
  }

  /// Locates the `emulator` command executable in the given Android SDK.
  static func locateEmulatorCommandExecutable(
    inAndroidSDK sdk: URL
  ) throws(Error) -> URL {
    // There a few different copies of emulator in the Android SDK. This seems
    // to be the one that works best. The one at tools/emulator can be an x86_64
    // executable on Apple Silicon Macs, which causes it to look for a non-existent
    // QEMU installation (for x86_64).
    let executable = sdk / "emulator/emulator"
    guard executable.exists() else {
      throw Error(.failedToLocateEmulatorCommandExecutable(executable))
    }
    return executable
  }

  /// Enumerates available virtual devices.
  static func enumerateVirtualDevices() async throws(Error) -> [AndroidVirtualDevice] {
    let avdManager = try locateAVDManagerExecutable()
    let output = try await Error.catch {
      try await Process.create(
        avdManager.path,
        arguments: ["list", "avd"]
      ).getOutput(excludeStdError: true)
    }

    let blocks = output.components(separatedBy: "---------")
    return blocks.compactMap { block -> AndroidVirtualDevice? in
      let lines = block.trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

      let nameKeyPrefix = "Name: "
      guard let nameLine = lines.first(where: { $0.starts(with: nameKeyPrefix) }) else {
        log.warning("Failed to locate name of AVD, skipping")
        log.debug("Output block lines: \(lines)")
        return nil
      }
      let name = nameLine.dropFirst(nameKeyPrefix.count)

      let pathKeyPrefix = "Path: "
      guard let pathLine = lines.first(where: { $0.starts(with: pathKeyPrefix) }) else {
        log.warning("Failed to locate path of AVD, skipping")
        log.debug("Output block lines: \(lines)")
        return nil
      }
      let path = pathLine.dropFirst(pathKeyPrefix.count)

      let configIni = URL(fileURLWithPath: String(path)) / "config.ini"
      let configIniContents: String
      do {
        configIniContents = try String(contentsOf: configIni)
      } catch {
        log.warning("Failed to read AVD config file; \(error.localizedDescription)")
        return nil
      }

      let values = parseIniRelaxed(configIniContents)
      guard let architectureString = values["hw.cpu.arch"] else {
        log.warning("Failed to locate AVD architecture in \(configIni.path)")
        return nil
      }

      guard let architecture = BuildArchitecture(fromAndroidName: architectureString) else {
        log.warning(
          "AVD '\(name)' has unrecognized architecture '\(architectureString)', skipping"
        )
        return nil
      }

      return AndroidVirtualDevice(
        name: String(name),
        architecture: architecture
      )
    }
  }

  /// Parses an ini file (ignoring unexpected constructs). This only understands
  /// the part of the ini language that we need to parse Android AVD config.ini files.
  private static func parseIniRelaxed(_ iniContents: String) -> [String: String] {
    var values: [String: String] = [:]
    for line in iniContents.split(separator: "\n") {
      let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.starts(with: "#") else {
        continue
      }

      let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2 else {
        log.warning("Failed to parse config.ini line; '\(line)'")
        continue
      }

      values[String(parts[0])] = String(parts[1])
    }
    return values
  }

  /// Converts a virtual device to its simulator representation.
  ///
  /// We take the list of booted virtual devices as input rather than fetching
  /// it within the function in order to force more efficient usage of the
  /// function. Otherwise, if someone wanted to convert an array of `n` virtual
  /// devices, we'd have to fetch the list of booted virtual devices `n` times.
  static func virtualDeviceToSimulator(
    _ device: AndroidVirtualDevice,
    bootedVirtualDevices: [AndroidVirtualDevice]
  ) async throws(Error) -> Simulator {
    let bootedDevice = bootedVirtualDevices.first { $0.name == device.name }
    return Simulator(
      id: bootedDevice?.adbIdentifier ?? "<not_booted \(device.name)>",
      name: device.name,
      isAvailable: true,
      isBooted: bootedVirtualDevices.contains { $0.name == device.name },
      os: .android,
      architecture: .arm64
    )
  }

  /// Enumerates booted Android virtual devices.
  static func enumerateBootedVirtualDevices()
    async throws(Error) -> [AndroidVirtualDevice]
  {
    let connectedDevices = try await Error.catch {
      try await AndroidDebugBridge.listConnectedDevices()
    }
    let connectedEmulators = try await connectedDevices
      .typedAsyncFilter { (device) async throws(Error) in
        try await Error.catch {
          try await AndroidDebugBridge.checkIsEmulator(device)
        }
      }

    let bootedAVDNames = try await connectedEmulators
      .asyncMap { (emulator) async throws(Error) in
        try await Error.catch {
          try await AndroidDebugBridge.getEmulatorAVDName(emulator)
        }
      }

    let allEmulators = try await enumerateVirtualDevices()
    return allEmulators.compactMap { emulator in
      guard let bootedIndex = bootedAVDNames.firstIndex(of: emulator.name) else {
        return nil
      }

      var emulator = emulator
      emulator.adbIdentifier = connectedEmulators[bootedIndex].identifier
      return emulator
    }
  }

  /// Boots a given Android virtual device.
  /// - Parameters:
  ///   - name: The name of the device to boot.
  ///   - additionalArguments: Additional arguments to pass to the 'emulator' CLI.
  ///   - checkAlreadyBooted: If `false`, skips checking whether the emulator has
  ///     already been booted. Setting this to `false` can lead to unintuitive
  ///     behaviour when `detach` is `true`.
  ///   - detach: If `true` the device gets started in a background process that
  ///     doesn't have its lifetime linked to Swift Bundler and gets its
  ///     stdout/stderr routed to /dev/null.
  static func bootVirtualDevice(
    named name: String,
    additionalArguments: [String],
    checkAlreadyBooted: Bool = true,
    detach: Bool = true
  ) async throws(Error) {
    let emulatorCommand = try locateEmulatorCommandExecutable()

    if checkAlreadyBooted {
      let bootedDevices = try await enumerateBootedVirtualDevices()
      guard !bootedDevices.map(\.name).contains(name) else {
        if detach {
          log.warning("Device already booted")
          return
        } else {
          throw Error(.cannotAttachToAlreadyBootedEmulator(name))
        }
      }
    }

    // Create the process without Process.create so that we can manage whether
    // or not the process gets killed along with Swift Bundler.
    let process = Process()
    process.executableURL = emulatorCommand
    process.arguments = ["-avd", name] + additionalArguments
    if detach {
      let devNull = FileHandle(forWritingAtPath: "/dev/null")
      process.standardError = devNull
      process.standardOutput = devNull
      try Error.catch {
        try process.run()
      }
    } else {
      Process.processes.withLock { processes in
        processes.append(process)
      }
      try await Error.catch {
        try await process.runAndWait()
      }
    }
  }
}
