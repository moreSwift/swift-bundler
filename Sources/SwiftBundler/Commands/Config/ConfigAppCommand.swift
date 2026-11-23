import ArgumentParser
import Foundation

/// The subcommand for inspecting and modifying Swift Bundler app configuration.
struct ConfigAppCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "app",
    abstract: "View and manage app configuration.",
    subcommands: [
      ConfigAppListCommand.self,
      // Deprecated commands
      DeprecatedConfigAppListCommand.self,
    ]
  )
}
