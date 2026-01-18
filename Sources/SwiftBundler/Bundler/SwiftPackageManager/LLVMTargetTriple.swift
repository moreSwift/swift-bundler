/// An LLVM-compatible target triple.
struct LLVMTargetTriple: CustomStringConvertible {
  /// The target architecture.
  var architecture: BuildArchitecture
  /// The triple's vendor (`"apple"` for Apple devices).
  var vendor: Vendor
  /// The target system (e.g. iOS 15.0).
  var system: System
  /// The target environment/ABI. This is where we specify whether the platform
  /// is a simulator or not.
  var abi: ABI?

  var description: String {
    // TODO: Ideally we'd be able to reuse BuildArchitecture.argument(for:) here
    var triple = ""
    switch architecture {
      case .x86_64, .armv7:
        triple = architecture.rawValue
      case .arm64:
        switch vendor {
          case .apple:
            triple = architecture.rawValue
          case .unknown:
            triple = "aarch64"
        }
    }
      
    triple += "-\(vendor.rawValue)-\(system.description)"
    if let abi {
      triple += "-\(abi.description)"
    }
    return triple
  }

  enum Vendor: String {
    case apple
    case unknown
  }

  struct System: CustomStringConvertible {
    var name: String
    var version: String?

    var description: String {
      "\(name)\(version ?? "")"
    }

    static func iOS(_ version: String) -> Self {
      Self(name: "ios", version: version)
    }

    static func visionOS(_ version: String) -> Self {
      Self(name: "xros", version: version)
    }

    static func tvOS(_ version: String) -> Self {
      Self(name: "tvos", version: version)
    }

    static func macOS(_ version: String) -> Self {
      Self(name: "macosx", version: version)
    }

    static let linux = Self(name: "linux")

    static let windows = Self(name: "windows")
  }

  enum ABI: CustomStringConvertible {
    /// The ABI used to target Apple platform simulators.
    case simulator
    /// The ABI usually used by Swift on Linux.
    case gnu
    /// The ABI used by Swift on Windows.
    case msvc
    /// The ABI used by Mac Catalyst.
    case macabi
    /// The ABI used by Android.
    case android(api: Int)

    var description: String {
      switch self {
        case .simulator: "simulator"
        case .gnu: "gnu"
        case .msvc: "msvc"
        case .macabi: "macabi"
        case .android(let api): "android\(api)"
      }
    }
  }

  /// Creates the target triple for the specified Apple platform.
  static func apple(
    _ architecture: BuildArchitecture,
    _ system: System,
    _ abi: ABI? = nil
  ) -> Self {
    Self(
      architecture: architecture,
      vendor: .apple,
      system: system,
      abi: abi
    )
  }

  static func linux(_ architecture: BuildArchitecture) -> Self {
    Self(
      architecture: architecture,
      vendor: .unknown,
      system: .linux,
      abi: .gnu
    )
  }

  static func windows(_ architecture: BuildArchitecture) -> Self {
    Self(
      architecture: architecture,
      vendor: .unknown,
      system: .windows,
      abi: .msvc
    )
  }

  static func android(_ architecture: BuildArchitecture, api: Int) -> Self {
    Self(
      architecture: architecture,
      vendor: .unknown,
      system: .linux,
      abi: .android(api: api)
    )
  }
}
