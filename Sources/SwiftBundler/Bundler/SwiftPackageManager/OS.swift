import Foundation

/// An OS to build for.
enum OS: String, Sendable, Hashable, CaseIterable {
  case macOS
  case iOS
  case visionOS
  case tvOS
  case linux
  case windows
  case android

  init?(rawValue: String) {
    if let value = Self.allCases.first(where: { $0.rawValue == rawValue }) {
      self = value
    } else if let value = Self.allCases.first(where: { $0.name == rawValue }) {
      self = value
    } else {
      return nil
    }
  }

  /// The display name of the os.
  var name: String {
    switch self {
      case .macOS, .iOS, .visionOS, .tvOS:
        return rawValue
      case .linux:
        return "Linux"
      case .windows:
        return "Windows"
      case .android:
        return "Android"
    }
  }

  /// The OS's corresponding physical platform.
  ///
  /// Some OS's only have a physical platform associated with them
  /// (such as Linux), while others, such as iOS, have simulated platforms
  /// associated with them in addition to physical platforms. Android's
  /// emulators are the same platform as Android (as they are full emulators
  /// not just simulators).
  var physicalPlatform: Platform {
    switch self {
      case .iOS: .iOS
      case .tvOS: .tvOS
      case .visionOS: .visionOS
      case .macOS: .macOS
      case .linux: .linux
      case .windows: .windows
      case .android: .android
    }
  }

  /// Whether the OS is an Apple OS or not.
  var isAppleOS: Bool {
    switch self {
      case .macOS, .iOS, .visionOS, .tvOS:
        true
      case .linux, .windows, .android:
        false
    }
  }

  /// Gets the OS as an Apple OS if it is one.
  var asAppleOS: AppleOS? {
    switch self {
      case .macOS: .macOS
      case .iOS: .iOS
      case .tvOS: .tvOS
      case .visionOS: .visionOS
      case .linux, .windows, .android: nil
    }
  }
}
