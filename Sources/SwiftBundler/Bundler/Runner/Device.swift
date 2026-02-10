import ArgumentParser
import Foundation

/// A device that can be used to run apps.
enum Device: Sendable, Equatable, CustomStringConvertible {
  case host(HostPlatform, BuildArchitecture)
  /// Mac Catalyst isn't a host platform, because we don't run Swift Bundler under
  /// Mac Catalyst, so it can't live under the `.host` case. But for all intents
  /// and purposes, this `.macCatalyst` case functions very similarly to `.host`.
  case macCatalyst(BuildArchitecture)
  case connected(ConnectedDevice)

  var description: String {
    switch self {
      case .host(let platform, let architecture):
        return "\(platform.platform.name) host machine (arch: \(architecture.rawValue))"
      case .macCatalyst(let architecture):
        return "Mac Catalyst host machine (arch: \(architecture.rawValue))"
      case .connected(let device):
        return "\(device.name) (\(device.platform.platform), id: \(device.id))"
    }
  }

  /// The device's id (as decided by the device's corresponding management tool
  /// such as devicectl or adb).
  var id: String? {
    switch self {
      case .host, .macCatalyst:
        return nil
      case .connected(let device):
        return device.id
    }
  }

  /// The device's platform.
  var platform: Platform {
    switch self {
      case .host(let platform, _):
        return platform.platform
      case .macCatalyst:
        return .macCatalyst
      case .connected(let device):
        return device.platform.platform
    }
  }

  /// The device's architecture.
  var architecture: BuildArchitecture {
    switch self {
      case .host(_, let architecture), .macCatalyst(let architecture):
        return architecture
      case .connected(let device):
        return device.architecture
    }
  }

  init(
    applePlatform platform: ApplePlatform,
    name: String,
    id: String,
    status: ConnectedDevice.Status,
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
        self.init(
          nonMacApplePlatform: nonMacPlatform,
          name: name,
          id: id,
          status: status,
          architecture: architecture
        )
    }
  }

  init(
    nonMacApplePlatform platform: NonMacApplePlatform,
    name: String,
    id: String,
    status: ConnectedDevice.Status,
    architecture: BuildArchitecture
  ) {
    let device = ConnectedDevice(
      platform: platform,
      name: name,
      id: id,
      status: status,
      architecture: architecture
    )
    self = .connected(device)
  }
}
