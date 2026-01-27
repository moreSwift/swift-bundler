import Foundation
import ErrorKit

/// A platform to build for.
enum Platform: String, CaseIterable {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``Platform``.
  enum ErrorMessage: Throwable {
    case invalidAndroidAPIVersion(String)
    case platformVersionRequiredForPlatform(Platform)

    var userFriendlyMessage: String {
      switch self {
        case .invalidAndroidAPIVersion(let version):
          "Invalid Android API version '\(version)'; expected integer"
        case .platformVersionRequiredForPlatform(let platform):
          "Platform '\(platform)' requires a platform version to create a target triple"
      }
    }
  }

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
  case android

  enum Partitioned {
    case linux
    case windows
    case android
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
      case .android:
        return .android
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
      case .android:
        return "Android"
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
      case .macOS, .linux, .windows, .android:
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
      case .android:
        return "android"
    }
  }

  /// Whether the platform uses the host architecture or not. Simulators
  /// and Mac Catalyst use the host architecture.
  var usesHostArchitecture: Bool {
    switch partitioned {
      case .apple(let applePlatform):
        applePlatform.usesHostArchitecture
      case .android:
        false
      case .linux, .windows:
        true
    }
  }

  /// The set of compilation architectures supported by the platform.
  var supportedCompilationArchitectures: [BuildArchitecture] {
    switch self {
      case .macOS, .macCatalyst:
        [.x86_64, .arm64]
      case .iOS, .visionOS, .tvOS:
        [.arm64]
      case .linux, .windows:
        [.x86_64, .arm64]
      case .android:
        [.x86_64, .arm64, .armv7]
      case .iOSSimulator, .visionOSSimulator, .tvOSSimulator:
        [.x86_64, .arm64]
    }
  }

  /// Whether the platform supports multi-architecture builds.
  var supportsMultiArchitectureBuilds: Bool {
    switch self {
      case .macOS, .macCatalyst, .iOSSimulator, .visionOSSimulator, .tvOSSimulator:
        true
      case .linux, .windows, .android, .iOS, .visionOS, .tvOS:
        false
    }
  }

  /// Default compilation architecture used when targeting the platform without
  /// a user-specified target architecture.
  func defaultCompilationArchitecture(_ host: BuildArchitecture) -> BuildArchitecture {
    switch self {
      case .macOS, .macCatalyst, .linux, .windows, .iOSSimulator,
        .visionOSSimulator, .tvOSSimulator:
        host
      case .android, .iOS, .visionOS, .tvOS:
        .arm64
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
      case .linux, .windows, .android: return nil
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
      case .android: return .android
    }
  }

  /// The platform's executable file extension if any.
  var executableFileExtension: String? {
    switch self {
      case .windows:
        return "exe"
      case .macOS, .macCatalyst, .linux, .android, .iOS, .iOSSimulator,
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

  /// Gets the target triple corresponding to this platform, the given architecture,
  /// and the given platform version.
  func targetTriple(
    withArchitecture architecture: BuildArchitecture,
    andPlatformVersion platformVersion: String?
  ) throws(Error) -> LLVMTargetTriple {
    switch self.partitioned {
      case .apple(let applePlatform):
        guard let platformVersion else {
          throw Error(.platformVersionRequiredForPlatform(self))
        }
        switch applePlatform {
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
        }
      case .linux:
        return .linux(architecture)
      case .windows:
        return .windows(architecture)
      case .android:
        guard let platformVersion else {
          throw Error(.platformVersionRequiredForPlatform(self))
        }
        guard let api = Int(platformVersion) else {
          throw Error(.invalidAndroidAPIVersion(platformVersion))
        }
        return .android(architecture, api: api)
    }
  }

  static let androidAPI = 28

  /// Gets the platform version corresponding to this platform.
  func platformVersion(from manifest: PackageManifest) -> String? {
    if let platform = self.asApplePlatform {
      manifest.platformVersion(for: platform)
    } else if self == .android {
      // TODO: Make this configurable
      String(Self.androidAPI)
    } else {
      nil
    }
  }
}

extension Platform: Equatable {
  public static func == (lhs: Platform, rhs: AppleSDKPlatform) -> Bool {
    lhs == rhs.platform
  }
}
