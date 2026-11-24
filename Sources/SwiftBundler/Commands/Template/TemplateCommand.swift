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
      TemplateUpdateCommand.self,
      // Deprecated commands
      DeprecatedTemplateListCommand.self,
    ]
  )
}
