/// A non-macOS Apple operating system.
enum NonMacAppleOS: Sendable, CaseIterable {
  case iOS
  case tvOS
  case visionOS

  /// The corresponding value in the generic Apple operating system enumeration.
  var os: AppleOS {
    switch self {
      case .iOS:
        return .iOS
      case .tvOS:
        return .tvOS
      case .visionOS:
        return .visionOS
    }
  }

  /// The name used for this OS when listed in a provisioning profile.
  var provisioningProfileName: String {
    switch self {
      case .iOS:
        return "iOS"
      case .tvOS:
        return "tvOS"
      case .visionOS:
        return "xrOS"
    }
  }

  /// The prefix that simulator runtimes matching this operating system will
  /// have.
  var simulatorRuntimePrefix: String {
    let osString: String
    switch self {
      case .iOS:
        osString = "iOS"
      case .tvOS:
        osString = "tvOS"
      case .visionOS:
        osString = "xrOS"
    }
    return "com.apple.CoreSimulator.SimRuntime.\(osString)-"
  }

  /// The simulator platform corresponding to this OS.
  var simulatorPlatform: NonMacApplePlatform {
    .simulator(self)
  }

  /// The physical device platform corresponding to this OS.
  var physicalPlatform: NonMacApplePlatform {
    .physical(self)
  }
}
