import Foundation
import ErrorKit

extension Xcodebuild {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``Xcodebuild``.
  enum ErrorMessage: Throwable {
    case failedToRunXcodebuild(command: String)
    case unsupportedPlatform(_ platform: Platform)
    case failedToMoveInterferingScheme(URL, destination: URL)
    case unsupportedArchitecture(ApplePlatform, BuildArchitecture)
    case universalBuildIncompatibleWithConcreteDestination
    case failedToLocateSuitableDestinationSimulator(
      [Simulator],
      AppleOS,
      BuildArchitecture
    )

    var userFriendlyMessage: String {
      switch self {
        case .failedToRunXcodebuild(let command):
          return "Failed to run '\(command)'"
        case .unsupportedPlatform(let platform):
          return """
            The xcodebuild backend doesn't support '\(platform.name)'. Only \
            Apple platforms are supported.
            """
        case .failedToMoveInterferingScheme(let scheme, _):
          let relativePath = scheme.path(relativeTo: URL(fileURLWithPath: "."))
          return """
            Failed to temporarily relocate Xcode scheme at '\(relativePath)' which \
            would otherwise interfere with the build process. Move it manually \
            and try again.
            """
        case .unsupportedArchitecture(let platform, let architecture):
          return """
            Architecture '\(architecture.rawValue)' isn't supported when targeting \
            '\(platform.platform.displayName)'
            """
        case .universalBuildIncompatibleWithConcreteDestination:
          return """
            A universal build was requested, but a destination device/simulator was
            also provided. Cannot build for multiple architectures when targeting a
            specific device.
            """
        case .failedToLocateSuitableDestinationSimulator(
          _,
          let os,
          let architecture
        ):
          return """
            Failed to locate suitable destination simulator with os \
            '\(os.name)' and architecture '\(architecture.rawValue)'. \
            xcodebuild requires that Swift Bundler provides a destination simulator \
            for single-architecture simulator builds. Run 'swift bundler simulators \
            list' to see available devices.
            """
      }
    }
  }
}
