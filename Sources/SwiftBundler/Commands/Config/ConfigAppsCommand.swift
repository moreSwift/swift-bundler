import ArgumentParser
import Foundation

/// The subcommand for inspecting and modifying Swift Bundler app configuration.
struct ConfigAppsCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "apps",
    abstract: "View and manage app configuration.",
    subcommands: [
      ConfigAppsListCommand.self,
    ],
    defaultSubcommand: ConfigAppsListCommand.self
  )
}
