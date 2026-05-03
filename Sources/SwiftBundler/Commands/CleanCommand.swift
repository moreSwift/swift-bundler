import ArgumentParser
import Foundation

/// The command for cleaning scratch files and caches.
struct CleanCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "clean",
    abstract: "Clean a project's scratch directory."
  )

  /// The directory containing the package to build.
  @Option(
    name: [.customShort("d"), .customLong("directory")],
    help: "The directory containing the package to build.",
    transform: URL.init(fileURLWithPath:)
  )
  var packageDirectory: URL?

  /// A custom scratch directory to clean. Defaults to `.build`.
  @Option(
    name: .customLong("scratch-path"),
    help: "A custom scratch directory path (default: .build)",
    transform: URL.init(fileURLWithPath:)
  )
  var scratchDirectory: URL?

  /// An alternative Swift toolchain to use.
  @Option(
    help: "An alternative Swift toolchain to use",
    transform: URL.init(fileURLWithPath:)
  )
  var toolchain: URL?

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages."
  )
  public var verbose = false

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    let packageDirectory = packageDirectory ?? URL.currentDirectory

    // Ensure that we're in a Swift package directory.
    let configurationFile = PackageConfiguration.standardConfigurationFileLocation(
      for: packageDirectory
    )
    guard configurationFile.exists() else {
      throw RichError(.missingConfigurationFile(configurationFile))
    }

    // Running 'swift package clean' also clears out '.build/bundler' on our
    // behalf, so we don't need to do anything more.
    let scratchDirectory = scratchDirectory ?? (packageDirectory / ".build")

    try await RichError<SwiftBundlerError>.catch {
      try await Process.create(
        SwiftPackageManager.swiftPath(toolchain: toolchain),
        arguments: [
          "package",
          "--scratch-path",
          scratchDirectory.path,
          "clean"
        ]
      ).runAndWait()
    }
  }
}
