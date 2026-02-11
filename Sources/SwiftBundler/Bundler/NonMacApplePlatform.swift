import Foundation

/// A non-macOS Apple platform. Used to model Apple platforms that can be
/// connected to computers to become run destinations.
enum NonMacApplePlatform: Sendable, Equatable {
  case physical(NonMacAppleOS)
  case simulator(NonMacAppleOS)

  var platform: Platform {
    switch self {
      case .physical(.iOS):
        return .iOS
      case .simulator(.iOS):
        return .iOSSimulator
      case .physical(.visionOS):
        return .visionOS
      case .simulator(.visionOS):
        return .visionOSSimulator
      case .physical(.tvOS):
        return .tvOS
      case .simulator(.tvOS):
        return .tvOSSimulator
    }
  }

  var isSimulator: Bool {
    switch self {
      case .physical:
        return false
      case .simulator:
        return true
    }
  }

  var os: NonMacAppleOS {
    switch self {
      case .physical(let os), .simulator(let os):
        return os
    }
  }
}
