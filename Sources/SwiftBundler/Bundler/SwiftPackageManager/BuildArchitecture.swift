import ArgumentParser
import Foundation

/// An architecture to build for.
enum BuildArchitecture: String, CaseIterable, ExpressibleByArgument {
  case x86_64  // swiftlint:disable:this identifier_name
  case arm64
  case armv7

  #if arch(x86_64)
    static let host: BuildArchitecture = .x86_64
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
  var androidName: String {
    switch self {
      case .arm64:
        "arm64-v8a"
      case .armv7:
        "armeabi-v7a"
      case .x86_64:
        "x86_64"
    }
  }
}
