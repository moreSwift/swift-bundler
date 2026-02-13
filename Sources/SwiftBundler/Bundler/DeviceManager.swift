/// A manager for connected and simulated devices that Swift Bundler knows
/// about.
enum DeviceManager {
  /// Lists physical connected devices known to Swift Bundler.
  static func listPhysicalConnectedDevices(
    oses: [OS]? = nil,
    searchTerm: String? = nil
  ) async throws(Error) -> [Device] {
    try await listDevices(
      platforms: oses?.map(\.physicalPlatform),
      searchTerm: searchTerm
    ).filter { !$0.isSimulator && !$0.isHost }
  }

  /// Lists all devices (including simulators and hosts) known to Swift Bundler.
  ///
  /// Sorts the devices for stability. See ``DeviceManager/sortDevices(_:)``.
  static func listDevices(
    platforms: [Platform]? = nil,
    searchTerm: String? = nil
  ) async throws(Error) -> [Device] {
    let hostPlatform = HostPlatform.hostPlatform
    let platforms = platforms ?? Platform.allCases

    var devices = [Device.host(hostPlatform)]
    if platforms.contains(where: \.isApplePlatform) && hostPlatform == .macOS {
      log.debug("Enumerating Apple devices and simulators")
      devices += try await Error.catch {
        try await AppleDeviceManager.listDevices()
      }
    }

    if platforms.contains(.android) && (try? AndroidSDKManager.locateAndroidSDK()) != nil {
      log.debug("Enumerating Android devices and simulators")
      devices += try await Error.catch {
        try await AndroidDebugBridge.listConnectedDevices()
          .typedAsyncMap { device in
            Device.androidDevice(AndroidDevice(
              id: device.identifier,
              name: try await AndroidDebugBridge.getModel(of: device),
              isEmulator: try await AndroidDebugBridge.checkIsEmulator(device),
              status: .available
            ))
          }
      }
    } else {
      log.debug("Android SDK not found")
    }

    if hostPlatform == .macOS {
      devices += [Device.macCatalyst]
    }

    devices = devices.filter { device in
      platforms.contains(device.platform)
    }.sorted()

    if let searchTerm, !searchTerm.isEmpty {
      return devices.filter { device in
        device.id?.contains(searchTerm) == true
        || device.name.contains(searchTerm)
      }.sorted { first, second in
        // Put exact id matches first
        if first.id != searchTerm && second.id == searchTerm {
          false
        } else {
          first <= second
        }
      }
    } else {
      return devices
    }
  }

  /// Resolves a device specifier (including simulators) with an optional
  /// platform hint.
  static func resolve(
    specifier: String,
    platform: Platform?
  ) async throws(Error) -> Device {
    guard specifier != "host" else {
      if platform == nil || platform == HostPlatform.hostPlatform.platform {
        return .host(HostPlatform.hostPlatform)
      } else {
        throw Error(.deviceNotFound(specifier: specifier, platform: platform))
      }
    }

    let platforms: [Platform]?
    if let platform {
      platforms = [platform]
    } else {
      platforms = nil
    }

    let matches = try await listDevices(
      platforms: platforms,
      searchTerm: specifier
    )

    guard let match = matches.first else {
      throw Error(.deviceNotFound(specifier: specifier, platform: platform))
    }

    if matches.count > 1 {
      log.warning(
        "Multiple devices matched '\(specifier)'; using '\(match.description)'"
      )
      log.debug("Matching devices: \(matches)")
    }

    return match
  }
}
