import Foundation

/// A simulator that Swift Bundler can operate on.
struct Simulator: Sendable, Equatable, Comparable {
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
        let device = AppleDevice(
          platform: .simulator(appleOS),
          name: name,
          id: id,
          status: isAvailable
            ? (isBooted ? .available : .summonable)
            : .unavailable(reason: "unavailable"),
          architecture: architecture
        )
        return .appleDevice(device)
      case .android:
        let device = AndroidDevice(
          id: id,
          name: name,
          isEmulator: true,
          status: isBooted ? .available : .summonable,
          architecture: architecture
        )
        return .androidDevice(device)
    }
  }

  static func < (_ lhs: Self, _ rhs: Self) -> Bool {
    // Define by proxy as a device
    lhs.device < rhs.device
  }
}
