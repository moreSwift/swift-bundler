import Foundation

/// An Apple OS to build for. Use this enum with care, because Mac Catalyst counts as
/// macOS but often requires special consideration.
enum AppleOS: String, CaseIterable {
  case macOS
  case iOS
  case visionOS
  case tvOS

  /// The display name of the os.
  var name: String {
    return rawValue
  }

  /// Gets the Apple OS' underlying ``OS``.
  var os: OS {
    switch self {
      case .macOS:
        return .macOS
      case .iOS:
        return .iOS
      case .visionOS:
        return .visionOS
      case .tvOS:
        return .tvOS
    }
  }
}
