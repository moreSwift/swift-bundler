import ArgumentParser
import Foundation

/// An architecture to build for.
enum BuildArchitecture: String, CaseIterable, ExpressibleByArgument {
  case x86_64  // swiftlint:disable:this identifier_name
  case x86
  case arm64
  case armv7

  #if arch(x86_64)
    static let host: BuildArchitecture = .x86_64
  #elseif arch(x86)
    static let host: BuildArchitecture = .x86
  #elseif arch(arm64)
    static let host: BuildArchitecture = .arm64
  #endif

  var defaultValueDescription: String {
    rawValue
  }

  /// Gets the argument's name in the form required for use in build arguments.
  /// Some platforms use different names for architectures.
  func argument(for platform: Platform) -> String {
    switch (platform, self) {
      case (.linux, .arm64), (.android, .arm64), (.windows, .arm64):
        return "aarch64"
      default:
        return rawValue
    }
  }

  /// The name that Android tools use for the architecture. This is
  /// different to the name that SwiftPM uses.
  var androidABIName: String {
    switch self {
      case .arm64:
        "arm64-v8a"
      case .armv7:
        "armeabi-v7a"
      case .x86_64:
        "x86_64"
      case .x86:
        "x86"
    }
  }

  var androidName: String {
    switch self {
      case .arm64, .x86_64, .x86:
        rawValue
      case .armv7:
        "arm"
    }
  }
}

extension BuildArchitecture {
  init?(fromAndroidName androidName: String) {
    switch androidName {
      case "arm64": self = .arm64
      case "arm": self = .armv7
      case "x86_64": self = .x86_64
      case "x86": self = .x86
      default: return nil
    }
  }

  init?(fromAndroidABI androidABI: String) {
    switch androidABI {
      case "arm64-v8a": self = .arm64
      case "armeabi-v7a": self = .armv7
      case "x86_64": self = .x86_64
      case "x86": self = .x86
      default: return nil
    }
  }
}
