import ArgumentParser
import Foundation
import Version

/// The root command of Swift Bundler.
public struct SwiftBundler: AsyncParsableCommand {
  /// The actual version of Swift Bundler.
  private static let _version = Version(3, 0, 0)

  /// The effective version of Swift Bundler. Under normal use this will match
  /// ``_version``, but the `SBUN_EFFECTIVE_VERSION` environment variable can
  /// be used to override the version that this build of Swift Bundler believes
  /// it is. Overriding Swift Bundler's effective version is generally only done
  /// to test configuration field deprecations and similar conditional behavior.
  public static var version: Version {
    if let effectiveVersion = ProcessInfo.processInfo.environment["_SBUN_EFFECTIVE_VERSION"],
      let parsedVersion = Version(tolerant: effectiveVersion)
    {
      parsedVersion
    } else {
      _version
    }
  }

  public static let identifier = "dev.moreswift.swift-bundler"

  public static let configuration = CommandConfiguration(
    commandName: "swift-bundler",
    abstract: "A tool for creating apps from Swift packages.",
    version: "v" + version.description,
    shouldDisplay: true,
    subcommands: [
      BundleCommand.self,
      RunCommand.self,
      CleanCommand.self,
      CreateCommand.self,
      ConvertCommand.self,
      ConfigCommand.self,
      MigrateCommand.self,
      DevicesCommand.self,
      SimulatorsCommand.self,
      TemplatesCommand.self,
      GenerateXcodeSupportCommand.self,
      ListIdentitiesCommand.self,
      DebugCommand.self,
    ]
  )

  /// Swift Bundler's git URL. Used when generating Swift packages that depend
  /// on the Swift Bundler runtime or builder API.
  public static let gitURL = URL(string: "https://github.com/moreSwift/swift-bundler")!

  /// Swift Bundler's GitHub URL for creating new issues. Used in diagnostics.
  public static let newIssueURL = gitURL / "issues/new"

  public func validate() throws {
    // Work around to allow SwiftBundler to be called twice in a single process.
    // Ideally this static cache variable wouldn't be needed, but I can't solve
    // that right now.
    BundleCommand.bundlerConfiguration = nil
  }

  public init() {}
}
