import Foundation

/// An Apple platform to build for.
enum ApplePlatform: String, CaseIterable {
  case macOS
  case macCatalyst
  case iOS
  case iOSSimulator
  case visionOS
  case visionOSSimulator
  case tvOS
  case tvOSSimulator

  enum Partitioned {
    case macOS
    case macCatalyst
    case other(NonMacApplePlatform)
  }

  /// The platform represented in a structure that partitions macOS from
  /// all other Apple platforms.
  var partitioned: Partitioned {
    switch self {
      case .macOS:
        return .macOS
      case .macCatalyst:
        return .macCatalyst
      case .iOS:
        return .other(.physical(.iOS))
      case .iOSSimulator:
        return .other(.simulator(.iOS))
      case .visionOS:
        return .other(.physical(.visionOS))
      case .visionOSSimulator:
        return .other(.simulator(.visionOS))
      case .tvOS:
        return .other(.physical(.tvOS))
      case .tvOSSimulator:
        return .other(.simulator(.tvOS))
    }
  }

  /// Whether the platform uses the host architecture or not. Simulators
  /// and Mac Catalyst use the host architecture.
  var usesHostArchitecture: Bool {
    isSimulator || self == .macCatalyst
  }

  /// Whether the platform is a simulator or not.
  var isSimulator: Bool {
    switch self {
      case .macOS, .macCatalyst, .iOS, .visionOS, .tvOS:
        return false
      case .iOSSimulator, .visionOSSimulator, .tvOSSimulator:
        return true
    }
  }

  /// The platform's os (e.g. ``ApplePlatform/iOS`` and ``ApplePlatform/iOSSimulator``
  /// are both ``AppleOS/iOS``).
  var os: AppleOS {
    switch self {
      case .macOS, .macCatalyst: return .macOS
      case .iOS, .iOSSimulator: return .iOS
      case .visionOS, .visionOSSimulator: return .visionOS
      case .tvOS, .tvOSSimulator: return .tvOS
    }
  }

  /// The underlying platform.
  var platform: Platform {
    switch self {
      case .macOS:
        return .macOS
      case .macCatalyst:
        return .macCatalyst
      case .iOS:
        return .iOS
      case .iOSSimulator:
        return .iOSSimulator
      case .visionOS:
        return .visionOS
      case .visionOSSimulator:
        return .visionOSSimulator
      case .tvOS:
        return .tvOS
      case .tvOSSimulator:
        return .tvOSSimulator
    }
  }

  /// Whether the platform requires app bundles to contain provisioning
  /// profiles or not.
  var requiresProvisioningProfiles: Bool {
    switch self {
      case .iOS, .tvOS, .visionOS:
        return true
      case .macOS, .macCatalyst, .iOSSimulator, .tvOSSimulator, .visionOSSimulator:
        return false
    }
  }

  /// The name for the corresponding platform in a SwiftPM manifest's JSON representation.
  /// Some platforms map to the same manifest name as each other (e.g. iOS and iOS Simulator).
  var manifestPlatformName: String {
    switch self {
      case .macOS: "macos"
      case .macCatalyst: "maccatalyst"
      case .iOS, .iOSSimulator: "ios"
      case .visionOS, .visionOSSimulator: "visionos"
      case .tvOS, .tvOSSimulator: "tvos"
    }
  }

  /// The minimum version of this platform that Swift supports.
  var minimumSwiftSupportedVersion: String {
    switch self {
      case .macOS:
        return "10.9"
      case .macCatalyst:
        return "13.1"
      case .iOS, .iOSSimulator:
        return "7.0"
      case .visionOS, .visionOSSimulator:
        return "0.0"
      case .tvOS, .tvOSSimulator:
        return "9.0"
    }
  }

  /// The name of this platform when used in Xcode build destinations.
  var xcodeDestinationName: String {
    switch self {
      case .macOS, .macCatalyst:
        return "macOS"
      case .iOS:
        return "iOS"
      case .iOSSimulator:
        return "iOS Simulator"
      case .tvOS:
        return "tvOS"
      case .tvOSSimulator:
        return "tvOS Simulator"
      case .visionOS:
        return "visionOS"
      case .visionOSSimulator:
        return "visionOS Simulator"
    }
  }

  /// The device names when passed to `--target-device` in actool.
  var actoolTargetDeviceNames: [String] {
    switch self {
      case .macOS:
        return ["mac"]
      case .macCatalyst:
        return ["mac", "ipad", "iphone"]
      case .iOS, .iOSSimulator:
        return ["iphone", "ipad"]
      case .tvOS, .tvOSSimulator:
        return ["tv"]
      case .visionOS, .visionOSSimulator:
        return ["vision"]
    }
  }

  var xcodeDestinationVariant: String? {
    switch self {
      case .macCatalyst:
        return "Mac Catalyst"
      case .macOS, .iOS, .iOSSimulator, .tvOS, .tvOSSimulator,
        .visionOS, .visionOSSimulator:
        return nil
    }
  }

  static func parseXcodeDestinationName(_ destinationName: String, _ variant: String?) -> Self? {
    Self.allCases.first { destination in
      destination.xcodeDestinationName == destinationName
        && destination.xcodeDestinationVariant == variant
    }
  }
}
