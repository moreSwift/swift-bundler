import Foundation

struct Simulator: Sendable, Equatable {
  /// The simulator's id according to its corresponding management tool.
  var id: String
  /// The simulator's user facing name.
  var name: String
  /// Whether the simulator is available or not. A possible reason that an Apple
  /// simulator might not be available would be if its corresponding platform SDK
  /// isn't installed.
  var isAvailable: Bool
  /// Whether the simulator is currently booted or not.
  var isBooted: Bool
  /// The simulator's OS.
  var os: SimulatorOS
  /// The simulator's architecture
  var architecture: BuildArchitecture

  /// A representation of the simulator as a device.
  var device: Device {
    switch os {
      case .apple(let appleOS):
        let device = ConnectedAppleDevice(
          platform: .simulator(appleOS),
          name: name,
          id: id,
          status: isAvailable
            ? (isBooted ? .available : .summonable)
            : .unavailable(message: "unavailable"),
          architecture: architecture
        )
        return .connectedAppleDevice(device)
      case .android:
        let device = ConnectedAndroidDevice(
          id: id,
          name: name,
          isEmulator: true,
          status: isBooted ? .available : .unavailable,
          architecture: architecture
        )
        return .connectedAndroidDevice(device)
    }
  }
}
