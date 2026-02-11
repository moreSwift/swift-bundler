import Foundation

/// An OS to build for.
enum OS: String, CaseIterable {
  case macOS
  case iOS
  case visionOS
  case tvOS
  case linux
  case windows
  case android

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
