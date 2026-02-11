/// An OS that we support simulators for.
enum SimulatorOS: Sendable, Hashable, RawRepresentable, CaseIterable {
  case apple(NonMacAppleOS)
  case android

  static var allCases: [SimulatorOS] {
    NonMacAppleOS.allCases.map(Self.apple) + [.android]
  }

  /// The simulator OS's ``OS`` representation.
  var os: OS {
    switch self {
      case .apple(let os):
        // os os os, oi oi oi
        os.os.os
      case .android:
        .android
    }
  }

  /// Whether or not the OS is an Apple OS.
  var isAppleOS: Bool {
    switch self {
      case .apple: true
      case .android: false
    }
  }

  var rawValue: String {
    switch self {
      case .apple(let os):
        os.rawValue
      case .android:
        "android"
    }
  }

  var displayName: String {
    switch self {
      case .apple(let os):
        os.os.name
      case .android:
        "Android"
    }
  }

  init?(rawValue: String) {
    if let os = NonMacAppleOS(rawValue: rawValue) {
      self = .apple(os)
    } else if rawValue == "android" {
      self = .android
    } else {
      return nil
    }
  }
}
