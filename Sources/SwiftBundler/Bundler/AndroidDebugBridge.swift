import Foundation

/// A utility that wraps the `adb` cli.
enum AndroidDebugBridge {
  /// Locates the `adb` executable.
  static func locateADBExecutable() throws(Error) -> URL {
    let sdk = try Error.catch {
      try AndroidSDKManager.locateAndroidSDK()
    }
    return try locateADBExecutable(inAndroidSDK: sdk)
  }

  /// Locates the `adb` executable in the given Android SDK.
  static func locateADBExecutable(inAndroidSDK sdk: URL) throws(Error) -> URL {
    let executable = sdk / "platform-tools/adb"
    guard executable.exists() else {
      throw Error(.failedToLocateADBExecutable(executable))
    }
    return executable
  }

  /// A connected device as seen by ADB.
  struct ConnectedDevice: Hashable, Sendable {
    /// The device's ADB identifier.
    var identifier: String
  }

  /// Lists connected Android devices and emulators.
  static func listConnectedDevices() async throws(Error) -> [ConnectedDevice] {
    let adb = try locateADBExecutable()
    let output = try await Error.catch {
      try await Process.create(
        adb.path,
        arguments: ["devices"]
      ).getOutput()
    }

    // Example output:
    //
    // List of devices attached
    // adb-53271JEKB02001-QRdsLi._adb-tls-connect._tcp.        device
    let lines = output.trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: "\n")
      .dropFirst()
    var devices: [ConnectedDevice] = []
    for line in lines {
      // Skip known status lines. If turn out to be more than just these two then
      // we should handle this more generally.
      if line == "* daemon started successfully" || line == "List of devices attached" {
        continue
      }

      let parts = line.split(separator: "\t")
      guard parts.count == 2, parts[1] == "device" else {
        log.warning("Failed to parse line of 'adb devices' output: '\(line)'")
        continue
      }

      devices.append(ConnectedDevice(identifier: String(parts[0])))
    }

    return devices
  }

  /// Gets the model of the given device.
  static func getModel(of device: ConnectedDevice) async throws(Error) -> String {
    let adb = try locateADBExecutable()
    let process = Process.create(
      adb.path,
      arguments: ["-s", device.identifier, "shell", "getprop", "ro.product.model"]
    )

    let output = try await Error.catch {
      try await process.getOutput()
    }
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Checks whether the given device is an emulator or not.
  static func checkIsEmulator(_ device: ConnectedDevice) async throws(Error) -> Bool {
    let adb = try locateADBExecutable()
    let process = Process.create(
      adb.path,
      arguments: ["-s", device.identifier, "emu"]
    )

    do {
      try await process.runAndWait()
      return true
    } catch {
      switch error.message {
        case .nonZeroExitStatusWithOutput(_, _, 1):
          return false
        default:
          throw Error(.failedToCheckWhetherDeviceIsEmulator(device.identifier), cause: error)
      }
    }
  }

  /// Gets the name of the device's corresponding AVD assuming that the device
  /// is an emulator.
  static func getEmulatorAVDName(_ device: ConnectedDevice) async throws(Error) -> String {
    let adb = try locateADBExecutable()
    let process = Process.create(
      adb.path,
      arguments: ["-s", device.identifier, "emu", "avd", "name"]
    )

    let message = ErrorMessage.failedToGetEmulatorAVDName(device.identifier)
    let output = try await Error.catch(withMessage: message) {
      try await process.getOutput()
    }

    // Example output:
    //
    // Pixel_6_API_33
    // OK
    let lines = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\r\n")
    guard lines.count == 2, lines[1] == "OK" else {
      print(lines)
      throw Error(.failedToParseEmulatorAVDNameOutput(output))
    }

    return String(lines[0])
  }
}
