import ArgumentParser
import Foundation

/// The subcommand for managing and listing available package templates.
struct TemplateCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "template",
    abstract: "Manage and list available package templates.",
    subcommands: [
      TemplateListCommand.self,
      TemplateInfoCommand.self,
      TemplateRepoCommand.self,
      // Deprecated commands
      DeprecatedTemplateListCommand.self,
      DeprecatedTemplateUpdateCommand.self,
    ]
  )
}
