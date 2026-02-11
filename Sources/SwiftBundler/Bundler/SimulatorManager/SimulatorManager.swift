/// A general simulator manager supporting both Apple simulators and Android emulators.
enum SimulatorManager {
  /// Lists all available simulators, optionally matching a specific set of OSes
  /// and a search term if given.
  static func listSimulators(
    oses: [SimulatorOS]? = nil,
    searchTerm: String? = nil
  ) async throws(Error) -> [Simulator] {
    var simulators: [Simulator] = []

    let oses = oses ?? SimulatorOS.allCases
    if HostPlatform.hostPlatform == .macOS && oses.contains(where: { $0.isAppleOS }) {
      log.debug("Enumerating Apple simulators")
      let appleSimulators = try await Error.catch {
        try await AppleSimulatorManager.listAvailableSimulators()
      }
      simulators.append(contentsOf: appleSimulators)
    }

    if oses.contains(.android) {
      if (try? AndroidSDKManager.locateAndroidSDK()) == nil {
        log.warning("Android SDK not found, skipping Android emulators")
      } else {
        log.debug("Enumerating Android emulators")
        let emulators = try await Error.catch {
          try await AndroidVirtualDeviceManager.enumerateVirtualDevices()
        }
        let bootedVirtualDevices = try await Error.catch {
          try await AndroidVirtualDeviceManager.enumerateBootedVirtualDevices()
        }
        let androidSimulators = try await Error.catch {
          try await emulators.typedAsyncMap { emulator in
            try await AndroidVirtualDeviceManager.virtualDeviceToSimulator(
              emulator,
              bootedVirtualDevices: bootedVirtualDevices
            )
          }
        }
        simulators.append(contentsOf: androidSimulators)
      }
    }

    // Sort by name, then id, then os. The idea behind this is just to enforce
    // a stable ordering. The ordering that we've chosen isn't that important
    // in and of itself.
    simulators = simulators.sorted { first, second in
      first.name < second.name || (
        first.name == second.name && (
          first.id < second.id || (
            first.id == second.id && first.os.displayName < second.os.displayName
          )
        )
      )
    }

    if let searchTerm {
      return simulators.filter { simulator in
        simulator.name.contains(searchTerm) || simulator.id == searchTerm
      }
    } else {
      return simulators
    }
  }

  /// Locates a simulator by name or id. Supports partial matching.
  static func locateSimulator(
    oses: [SimulatorOS]? = nil,
    searchTerm: String
  ) async throws(Error) -> Simulator {
    let simulators = try await listSimulators(oses: oses, searchTerm: searchTerm)
    guard let simulator = simulators.first else {
      throw Error(.failedToLocateSimulator(oses, searchTerm))
    }

    if simulators.count > 1 {
      log.warning(
        "Multiple simulators match '\(searchTerm)', using '\(simulator.name)'"
      )
      log.debug("Matching simulators: \(simulators.map(\.id))")
    }

    return simulator
  }

  /// Boots the given simulator.
  static func bootSimulator(_ simulator: Simulator) async throws(Error) {
    switch simulator.os {
      case .apple(_):
        try await Error.catch {
          try await AppleSimulatorManager.bootSimulator(id: simulator.id)
          log.info("Opening 'Simulator.app'")
          try await AppleSimulatorManager.openSimulatorApp()
        }
      case .android:
        try await Error.catch {
          try await AndroidVirtualDeviceManager.bootVirtualDevice(
            AndroidVirtualDevice(name: simulator.id),
            additionalArguments: []
          )
        }
    }
  }
}
