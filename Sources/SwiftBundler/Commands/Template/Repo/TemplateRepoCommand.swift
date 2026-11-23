import ArgumentParser
import Foundation

/// The subcommand for managing and listing available package template repositories.
struct TemplateRepoCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "repo",
    abstract: "Manage and list available package template repositories.",
    subcommands: [
      TemplateRepoListCommand.self,
      TemplateRepoUpdateCommand.self,
    ]
  )
}
