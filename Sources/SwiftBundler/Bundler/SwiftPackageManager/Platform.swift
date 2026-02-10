import Foundation

/// A platform to build for.
enum Platform: String, CaseIterable {
  case macOS
  case macCatalyst
  case iOS
  case iOSSimulator
  case visionOS
  case visionOSSimulator
  case tvOS
  case tvOSSimulator
  case linux
  case windows

  enum Partitioned {
    case linux
    case windows
    case apple(ApplePlatform)
  }

  /// The platform represented in a structure that partitions Apple platforms
  /// from the rest.
  var partitioned: Partitioned {
    switch self {
      case .linux:
        return .linux
      case .windows:
        return .windows
      case .macOS:
        return .apple(.macOS)
      case .macCatalyst:
        return .apple(.macCatalyst)
      case .iOS:
        return .apple(.iOS)
      case .iOSSimulator:
        return .apple(.iOSSimulator)
      case .visionOS:
        return .apple(.visionOS)
      case .visionOSSimulator:
        return .apple(.visionOSSimulator)
      case .tvOS:
        return .apple(.tvOS)
      case .tvOSSimulator:
        return .apple(.tvOSSimulator)
    }
  }

  /// The platform's display name.
  var displayName: String {
    switch self {
      case .macOS:
        return "macOS"
      case .macCatalyst:
        return "Mac Catalyst"
      case .iOS:
        return "iOS"
      case .iOSSimulator:
        return "iOS Simulator"
      case .visionOS:
        return "visionOS"
      case .visionOSSimulator:
        return "visionOS Simulator"
      case .tvOS:
        return "tvOS"
      case .tvOSSimulator:
        return "tvOS Simulator"
      case .linux:
        return "Linux"
      case .windows:
        return "Windows"
    }
  }

  /// Architectures supported when targeting the platform.
  var supportedArchitectures: [BuildArchitecture] {
    switch partitioned {
      case .apple(let applePlatform):
        applePlatform.supportedArchitectures
      case .linux, .windows:
        [.x86_64, .arm64]
    }
  }

  /// Gets the default architecture to use when building for the platform.
  func defaultTargetArchitecture(hostArchitecture: BuildArchitecture) -> BuildArchitecture {
    switch partitioned {
      case .apple(let applePlatform):
        applePlatform.defaultTargetArchitecture(hostArchitecture: hostArchitecture)
      case .linux, .windows:
        hostArchitecture
    }
  }

  /// The platform's name.
  var name: String {
    return rawValue
  }

  // TODO: Move this to `ApplePlatform` and refactor usages accordingly
  /// The suffix used for the Xcode product directory produced when building for
  /// this platform.
  var xcodeProductDirectorySuffix: String? {
    switch self {
      case .macCatalyst:
        "maccatalyst"
      case .iOS, .iOSSimulator, .visionOS, .visionOSSimulator, .tvOS, .tvOSSimulator:
        sdkName
      case .macOS, .linux, .windows:
        nil
    }
  }

  // TODO: Move this to `ApplePlatform` and refactor usages accordingly
  /// The platform's sdk name (e.g. for `iOS` it's `iphoneos`).
  var sdkName: String {
    switch self {
      case .macOS, .macCatalyst:
        return "macosx"
      case .iOS:
        return "iphoneos"
      case .iOSSimulator:
        return "iphonesimulator"
      case .visionOS:
        return "xros"
      case .visionOSSimulator:
        return "xrsimulator"
      case .tvOS:
        return "appletvos"
      case .tvOSSimulator:
        return "appletvsimulator"
      case .linux:
        return "linux"
      case .windows:
        return "windows"
    }
  }

  /// Whether the platform is a simulator or not.
  var isSimulator: Bool {
    asApplePlatform?.isSimulator == true
  }

  /// Gets the platform as an ``ApplePlatform`` if it is in fact an Apple
  /// platform.
  var asApplePlatform: ApplePlatform? {
    switch self {
      case .macOS: return .macOS
      case .macCatalyst: return .macCatalyst
      case .iOS: return .iOS
      case .iOSSimulator: return .iOSSimulator
      case .visionOS: return .visionOS
      case .visionOSSimulator: return .visionOSSimulator
      case .tvOS: return .tvOS
      case .tvOSSimulator: return .tvOSSimulator
      case .linux, .windows: return nil
    }
  }

  /// Gets whether the platform is an Apple platform (e.g. iOS) or not.
  var isApplePlatform: Bool {
    asApplePlatform != nil
  }

  /// The platform's os (e.g. ``Platform/iOS`` and ``Platform/iOSSimulator``
  /// are both ``OS/iOS``).
  var os: OS {
    switch self {
      case .macOS, .macCatalyst: return .macOS
      case .iOS, .iOSSimulator: return .iOS
      case .visionOS, .visionOSSimulator: return .visionOS
      case .tvOS, .tvOSSimulator: return .tvOS
      case .linux: return .linux
      case .windows: return .windows
    }
  }

  /// The platform's executable file extension if any.
  var executableFileExtension: String? {
    switch self {
      case .windows:
        return "exe"
      case .macOS, .macCatalyst, .linux, .iOS, .iOSSimulator,
        .tvOS, .tvOSSimulator, .visionOS, .visionOSSimulator:
        return nil
    }
  }

  /// A simple lossless conversion.
  init(_ applePlatform: ApplePlatform) {
    switch applePlatform {
      case .macOS: self = .macOS
      case .macCatalyst: self = .macCatalyst
      case .iOS: self = .iOS
      case .iOSSimulator: self = .iOSSimulator
      case .visionOS: self = .visionOS
      case .visionOSSimulator: self = .visionOSSimulator
      case .tvOS: self = .tvOS
      case .tvOSSimulator: self = .tvOSSimulator
    }
  }

  func targetTriple(
    withArchitecture architecture: BuildArchitecture,
    andPlatformVersion platformVersion: String
  ) -> LLVMTargetTriple {
    switch self {
      case .iOS:
        return .apple(architecture, .iOS(platformVersion))
      case .visionOS:
        return .apple(architecture, .visionOS(platformVersion))
      case .tvOS:
        return .apple(architecture, .tvOS(platformVersion))
      case .iOSSimulator:
        return .apple(architecture, .iOS(platformVersion), .simulator)
      case .visionOSSimulator:
        return .apple(architecture, .visionOS(platformVersion), .simulator)
      case .tvOSSimulator:
        return .apple(architecture, .tvOS(platformVersion), .simulator)
      case .macOS:
        return .apple(architecture, .macOS(platformVersion))
      case .macCatalyst:
        return .apple(architecture, .iOS(platformVersion), .macabi)
      case .linux:
        return .linux(architecture)
      case .windows:
        return .windows(architecture)
    }
  }
}

extension Platform: Equatable {
  public static func == (lhs: Platform, rhs: AppleSDKPlatform) -> Bool {
    lhs == rhs.platform
  }
}
