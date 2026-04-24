import ArgumentParser
import Foundation

/// A device that can be used to run apps.
enum Device: Equatable, Sendable, CustomStringConvertible, Comparable {
  /// The host device.
  case host(HostPlatform, BuildArchitecture)
  /// A human readable (but incomplete) description of the device.
  case macCatalyst(BuildArchitecture)
  /// A connected Apple device or simulator.
  case appleDevice(AppleDevice)
  /// A connected Android device or emulator.
  case androidDevice(AndroidDevice)

  /// The status of a device.
  enum Status: Hashable, Sendable, CustomStringConvertible {
    /// The device is ready to use.
    case available
    /// The device can be summoned to be ready to use (generally means that
    /// it's a simulator/emulator).
    case summonable
    /// The device cannot be used.
    case unavailable(reason: String)

    var description: String {
      switch self {
        case .available:
          return "available"
        case .summonable:
          return "summonable"
        case .unavailable(let message):
          return "unavailable: \(message)"
      }
    }
  }

  /// A human readable (but incomplete) description of the device.
  var description: String {
    describe(includingId: true)
  }

  /// A human readable (but incomplete) description of the device.
  func describe(includingId includeId: Bool = false) -> String {
    switch self {
      case .host(let platform, let architecture):
        return "\(platform.platform.name) host machine (arch: \(architecture.rawValue))"
      case .macCatalyst(let architecture):
        return "Mac Catalyst host machine (arch: \(architecture.rawValue))"
      case .appleDevice(let device):
        return """
          \(device.name) (\(
            device.platform.platform
          )\(includeId ? ", id: \(device.id)" : ""))
          """
      case .androidDevice(let device):
        return "\(device.name) (Android\(device.isEmulator ? ", emulator" : ""))"
    }
  }

  /// The device's id according to its corresponding management tool (i.e.
  /// devicectl, simctl, or adb). Has a value of `nil` exactly when the device
  /// is the host platform (some code relies on this).
  var id: String? {
    switch self {
      case .host, .macCatalyst:
        return nil
      case .appleDevice(let device):
        return device.id
      case .androidDevice(let device):
        return device.id
    }
  }

  /// The status of the device.
  var status: Status {
    switch self {
      case .host: .available
      case .macCatalyst:
        if HostPlatform.hostPlatform == .macOS {
          .available
        } else {
          .unavailable(reason: "unavailable")
        }
      case .androidDevice(let device): device.status
      case .appleDevice(let device): device.status
    }
  }

  /// The device's user-facing name.
  var name: String {
    switch self {
      case .host: "host"
      case .macCatalyst: "macCatalyst"
      case .androidDevice(let device): device.name
      case .appleDevice(let device): device.name
    }
  }

  /// Whether the device is a simulator/emulator or not.
  var isSimulator: Bool {
    switch self {
      case .host, .macCatalyst: false
      case .appleDevice(let device): device.platform.isSimulator
      case .androidDevice(let device): device.isEmulator
    }
  }

  /// Whether the device is the host device or not.
  var isHost: Bool {
    switch self {
      case .host, .macCatalyst: true
      case .appleDevice, .androidDevice: false
    }
  }

  /// The device's platform.
  var platform: Platform {
    switch self {
      case .host(let platform, _):
        return platform.platform
      case .macCatalyst:
        return .macCatalyst
      case .appleDevice(let device):
        return device.platform.platform
      case .androidDevice:
        return .android
    }
  }

  /// The device's architecture.
  var architecture: BuildArchitecture {
    switch self {
      case .host(_, let architecture), .macCatalyst(let architecture):
        return architecture
      case .appleDevice(let device):
        return device.architecture
      case .androidDevice(let device):
        return device.architecture
    }
  }

  /// A multi-tiered index to use when sorting devices lexicographically. Should
  /// enforce a stable ordering.
  var lexicographicIndex: (Platform, UInt, Int, String, UInt, String) { // swiftlint:disable:this large_tuple
    let statusValue = switch status {
      case .available: 0
      case .summonable: 1
      case .unavailable: 2
    }
    return (
      // Sort by platform
      platform,
      // Put physical connected devices before simulators
      isSimulator ? 1 : 0,
      // Put available devices first within their group, followed by
      // summonabled devices, and then unavailable devices.
      statusValue,
      // Sort by name within each group
      name,
      // Put devices with no id first to break name ties
      id == nil ? 1 : 0,
      // Sort by id to break name ties
      id ?? "<no_id>"
    )
  }

  static func < (_ lhs: Self, _ rhs: Self) -> Bool {
    lhs.lexicographicIndex < rhs.lexicographicIndex
  }

  init(
    applePlatform platform: ApplePlatform,
    name: String,
    id: String,
    status: Device.Status,
    architecture: BuildArchitecture
  ) {
    switch platform.partitioned {
      case .macOS:
        // We assume that we only have one macOS destination so we ignore the
        // device id.
        self = .host(.macOS, architecture)
      case .macCatalyst:
        self = .macCatalyst(architecture)
      case .other(let nonMacPlatform):
        let device = AppleDevice(
          platform: nonMacPlatform,
          name: name,
          id: id,
          status: status,
          architecture: architecture
        )
        self = .appleDevice(device)
    }
  }
}
