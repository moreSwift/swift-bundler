import ArgumentParser
import Foundation

struct BundleArguments: ParsableArguments {
  /// The name of the app to build.
  @Argument(
    help: "The name of the app to build.")
  var appName: String?

  /// The bundler to use.
  @Option(
    help: "The bundler to use \(BundlerChoice.possibleValuesDescription).",
    transform: {
      guard let choice = BundlerChoice(rawValue: $0) else {
        throw SwiftBundlerError.invalidBundlerChoice($0)
      }
      return choice
    })
  var bundler: BundlerChoice?

  /// An alternative Swift toolchain to use.
  @Option(
    help: "An alternative Swift toolchain to use",
    transform: URL.init(fileURLWithPath:))
  var toolchain: URL?

  /// The directory containing the package to build.
  @Option(
    name: [.customShort("d"), .customLong("directory")],
    help:
      """
      The directory containing the package to build. This changes the working \
      directory before any other operation
      """,
    transform: URL.init(fileURLWithPath:))
  var packageDirectory: URL?

  /// Overrides the default configuration file location.
  @Option(
    name: [.customLong("config-file")],
    help: "Overrides the default configuration file location",
    transform: URL.init(fileURLWithPath:))
  var configurationFileOverride: URL?

  /// The directory to copy the built app bundle to on success.
  @Option(
    name: [.customShort("o"), .customLong("output-directory")],
    help: ArgumentHelp(
      "The directory to copy the built app bundle to on success.",
      visibility: .hidden
    ),
    transform: URL.init(fileURLWithPath:))
  var copyOutDirectory: URL?

  /// The directory containing the built products. Can only be set when
  /// `--skip-build` is supplied.
  @Option(
    name: .long,
    help:
      """
      The directory containing the built products. Can only be set when \
      `--skip-build` is supplied.
      """,
    transform: URL.init(fileURLWithPath:))
  var productsDirectory: URL?

  /// The build configuration to use.
  @Option(
    name: [.customShort("c"), .customLong("configuration")],
    help: "The build configuration to use \(BuildConfiguration.possibleValuesDescription).",
    transform: {
      guard let configuration = BuildConfiguration.init(rawValue: $0.lowercased()) else {
        throw SwiftBundlerError.invalidBuildConfiguration($0)
      }
      return configuration
    })
  var buildConfiguration = BuildConfiguration.debug

  /// The architectures to build for.
  @Option(
    name: [.customShort("a"), .customLong("arch")],
    parsing: .singleValue,
    help: {
      let possibleValues = BuildArchitecture.possibleValuesDescription
      let defaultValue = BuildArchitecture.host.rawValue
      return "The architectures to build for \(possibleValues). (default: [\(defaultValue)])"
    }(),
    transform: { string in
      guard let arch = BuildArchitecture.init(rawValue: string) else {
        throw SwiftBundlerError.invalidArchitecture(string)
      }
      return arch
    })
  var architectures: [BuildArchitecture] = []

  /// A custom scratch directory to use. Defaults to `.build`.
  @Option(
    name: .customLong("scratch-path"),
    help: "A custom scratch directory path (default: .build)",
    transform: URL.init(fileURLWithPath:))
  var scratchDirectory: URL?

  /// Additional arguments to pass to SwiftPM when building.
  @Option(
    name: .customLong("Xswiftpm"),
    parsing: .unconditionalSingleValue,
    help: "Additional arguments to pass to the SwiftPM builder when building.")
  var additionalSwiftPMArguments: [String] = []

  /// Additional arguments to pass to xcodebuild when building.
  @Option(
    name: .customLong("Xxcodebuild"),
    parsing: .unconditionalSingleValue,
    help: "Additional arguments to pass to the xcodebuild builder when building.")
  var additionalXcodeBuildArguments: [String] = []

  /// The platform to build for.
  @Option(
    name: .shortAndLong,
    help: {
      let possibleValues = Platform.possibleValuesDescription
      return "The platform to build for \(possibleValues). (default: macOS)"
    }(),
    transform: { string -> Platform in
      // also support getting a platform by its apple sdk equivalent.
      if let appleSDK = AppleSDKPlatform(rawValue: string) {
        return appleSDK.platform
      }

      guard let platform = Platform(rawValue: string) else {
        throw SwiftBundlerError.invalidPlatform(string)
      }
      return platform
    })
  var platform: Platform?

  /// The device to build for (or run on).
  @Option(
    name: [.customLong("device")],
    help: """
      A device name, id or search term to select a target device \
      (e.g. 'Apple TV' or \"John Appleseed's iPhone\"). Can be a simulator. \
      Use 'host' to refer to the host machine.
      """
  )
  var deviceSpecifier: String?

  @Flag(help: "Strip the main executable.")
  var strip = false

  #if os(macOS)
    @Option(
      name: [.customLong("simulator")],
      help: """
        A simulator name, id or search term to select the target simulator (e.g. \
        'iPhone 8' or 'Apple Vision Pro').
        """)
  #endif
  var simulatorSpecifier: String?

  /// A codesigning identity to use.
  #if os(macOS)
    @Option(
      name: .customLong("identity"),
      help: "The identity to use for codesigning")
  #endif
  var identity: String?

  /// A provisioning profile to use.
  #if os(macOS)
    @Option(
      name: .customLong("provisioning-profile"),
      help: """
        The provisioning profile to embed in the app (only applicable when \
        targeting non-macOS physical Apple devices).
        """,
      transform: URL.init(fileURLWithPath:))
  #endif
  var provisioningProfile: URL?

  /// If `true`, the application will be codesigned.
  #if os(macOS)
    @Flag(
      name: .customLong("codesign"),
      inversion: .prefixedNo,
      help: """
        Codesign the application. Defaults to false on macOS, Linux and \
        simulators, and true on non-macOS Apple devices.
        """)
  #endif
  var codesign: Bool?

  /// A codesigning entitlements file to use.
  #if os(macOS)
    @Option(
      name: .customLong("entitlements"),
      help: "Provide an entitlements file to use when codesigning.",
      transform: URL.init(fileURLWithPath:))
  #endif
  var entitlements: URL?

  /// If `true`, a universal application will be created (arm64 and x86_64).
  #if os(macOS)
    @Flag(
      name: .shortAndLong,
      help: "Build a universal application. Equivalent to '--arch arm64 --arch x86_64'.")
  #endif
  var universal = false

  /// If `true`, a stand-alone application will be created (which doesn't
  /// depend on any third-party system-wide dynamic libraries being installed
  /// such as gtk).
  #if os(macOS)
    @Flag(
      name: .customLong("experimental-stand-alone"),
      help: """
        Build an application which doesn't rely on any system-wide third-party \
        libraries being installed (such as gtk). This features is experimental \
        and potentially incompatible with '--universal', use with care.
        """
    )
  #endif
  var standAlone = false

  /// Builds with xcodebuild instead of swiftpm. This is the default when
  /// building for non-macOS Apple platforms from a Mac, since SwiftPM has
  /// issues doing so.
  #if os(macOS)
    @Flag(
      name: .customLong("xcodebuild"),
      help: """
        Build with xcodebuild instead of SwiftPM. This is the default when \
        building for non-macOS Apple platforms from a Mac, since SwiftPM has \
        issues doing so.
        """
    )
  #endif
  var xcodebuild = false

  /// Forces swiftpm to be used when targeting non-macOS Apple platforms. Use
  /// with care because many features, such as conditional dependencies in
  /// package manifests, may break.
  #if os(macOS)
    @Flag(
      name: .customLong("no-xcodebuild"),
      help: """
        Force swiftpm to be used when targeting non-macOS Apple platforms. Use \
        with care because many features, such as conditional dependencies in \
        package manifests, may break.
        """
    )
  #endif
  var noXcodebuild = false
}
