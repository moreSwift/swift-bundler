import ArgumentParser
import Foundation

/// Commands for inspecting the Swift Bundler installation itself.
struct SelfCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "self",
    abstract: "Meta commands operating on Swift Bundler itself.",
    subcommands: [SelfInfoCommand.self]
  )
}
