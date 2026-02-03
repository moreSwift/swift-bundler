import ArgumentParser
import Foundation
import Version

/// The root command of Swift Bundler.
public struct SwiftBundler: AsyncParsableCommand {
  public static let version = Version(3, 0, 0)
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
      MigrateCommand.self,
      DevicesCommand.self,
      SimulatorsCommand.self,
      EmulatorsCommand.self,
      TemplatesCommand.self,
      GenerateXcodeSupportCommand.self,
      ListIdentitiesCommand.self,
      DebugCommand.self
    ]
  )

  /// Swift Bundler's git URL. Used when generating Swift packages that depend
  /// on the Swift Bundler runtime or builder API.
  public static let gitURL = URL(string: "https://github.com/moreSwift/swift-bundler")!

  public func validate() throws {
    // Work around to allow SwiftBundler to be called twice in a single process.
    // Ideally this static cache variable wouldn't be needed, but I can't solve
    // that right now.
    BundleCommand.bundlerConfiguration = nil
  }

  public init() {}
}
