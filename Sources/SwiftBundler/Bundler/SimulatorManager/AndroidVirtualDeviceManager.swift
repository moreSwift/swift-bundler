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
  static func locateEmulatorCommandExecutable(inAndroidSDK sdk: URL) throws(Error) -> URL {
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
        arguments: ["list", "avd", "--compact"]
      ).getOutput(excludeStdError: true)
    }
    let lines = output.trimmingCharacters(in: .newlines).split(separator: "\n")
    return lines.map { deviceName in
      AndroidVirtualDevice(name: String(deviceName))
    }
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
    Simulator(
      id: device.name,
      name: device.name,
      isAvailable: true,
      isBooted: bootedVirtualDevices.contains { $0.name == device.name },
      os: .android
    )
  }

  /// Enumerates booted Android virtual devices.
  static func enumerateBootedVirtualDevices() async throws(Error) -> [AndroidVirtualDevice] {
    let connectedDevices = try await Error.catch {
      try await AndroidDebugBridge.listConnectedDevices()
    }
    let connectedEmulators = try await connectedDevices.typedAsyncFilter { (device) async throws(Error) in
      try await Error.catch {
        try await AndroidDebugBridge.checkIsEmulator(device)
      }
    }
    return try await connectedEmulators.asyncMap { (emulator) async throws(Error) in
      try await Error.catch {
        let name = try await AndroidDebugBridge.getEmulatorAVDName(emulator)
        return AndroidVirtualDevice(name: name)
      }
    }
  }

  /// Boots a given Android virtual device.
  /// - Parameters:
  ///   - device: The device to boot.
  ///   - additionalArguments: Additional arguments to pass to the 'emulator' CLI.
  ///   - checkAlreadyBooted: If `false`, skips checking whether the emulator has
  ///     already been booted. Setting this to `false` can lead to unintuitive
  ///     behaviour when `detach` is `true`.
  ///   - detach: If `true` the device gets started in a background process that
  ///     doesn't have its lifetime linked to Swift Bundler and gets its
  ///     stdout/stderr routed to /dev/null.
  static func bootVirtualDevice(
    _ device: AndroidVirtualDevice,
    additionalArguments: [String],
    checkAlreadyBooted: Bool = true,
    detach: Bool = true
  ) async throws(Error) {
    let emulatorCommand = try locateEmulatorCommandExecutable()

    if checkAlreadyBooted {
      let bootedDevices = try await enumerateBootedVirtualDevices()
      guard !bootedDevices.contains(device) else {
        if detach {
          log.warning("Device already booted")
          return
        } else {
          throw Error(.cannotAttachToAlreadyBootedEmulator(device.name))
        }
      }
    }

    // Create the process without Process.create so that we can manage whether
    // or not the process gets killed along with Swift Bundler.
    let process = Process()
    process.executableURL = emulatorCommand
    process.arguments = ["-avd", device.name] + additionalArguments
    if detach {
      let devNull = FileHandle(forWritingAtPath: "/dev/null")
      process.standardError = devNull
      process.standardOutput = devNull
      try Error.catch {
        try process.run()
      }
    } else {
      Process.processes.append(process)
      try await Error.catch {
        try await process.runAndWait()
      }
    }
  }
}
