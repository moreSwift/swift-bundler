import Foundation

/// Build-system agnostic build context.
struct GenericBuildContext {
  /// The root directory of the project.
  var projectDirectory: URL
  /// The scratch directory in use.
  var scratchDirectory: URL
  /// The build configuration to use.
  var configuration: BuildConfiguration
  /// The set of architectures to build for.
  var architectures: [BuildArchitecture]
  /// The platform to build for.
  var platform: Platform
  /// The platform version to build for.
  var platformVersion: String?
  /// Additional arguments to be passed to SwiftPM.
  var additionalArguments: [String]
  /// The Swift toolchain used.
  var swiftToolchain: URL?
}
