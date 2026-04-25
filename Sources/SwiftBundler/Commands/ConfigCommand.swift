import ArgumentParser
import Foundation

/// The subcommand for inspecting and modifying Swift Bundler package configuration.
struct ConfigCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "config",
    abstract: "View and manage Swift Bundler configuration.",
    subcommands: [
        ConfigAppsCommand.self,
    ]
  )
}
