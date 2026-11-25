import ArgumentParser
import Foundation
import Rainbow

/// The subcommand for getting info about a template.
struct TemplateInfoCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "info",
    abstract: "Get info about a template."
  )

  /// The template to get info about.
  @Argument(
    help: "The template to get info about."
  )
  var template: Template.Name

  @Option(
    name: [.customShort("r"), .customLong("repo")],
    help: "The repository containing the template."
  )
  var templateRepository: TemplateRepository.Name?

  @Flag(
    name: .customLong("no-auto-update"),
    help: "Disables template auto updating."
  )
  var disableAutoUpdating = false

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages."
  )
  public var verbose = false

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    let shouldAutoUpdate = !disableAutoUpdating && Env.autoUpdateTemplates
    let template = try await RichError<SwiftBundlerError>.catch {
      try await TemplateRepositoryManager.resolveTemplate(
        name: self.template,
        repository: templateRepository,
        autoUpdate: shouldAutoUpdate
      )
    }

    let exampleCommand =
      "swift-bundler create [app-name] --template \(template.name.name.quotedIfNecessary)"

    Output {
      Section("Template info") {
        KeyedList {
          KeyedList.Entry("Name", template.name.name)
          KeyedList.Entry("Description", template.configuration.description)
          KeyedList.Entry(
            "Minimum Swift version",
            template.configuration.minimumSwiftVersion?.description ?? "not specified"
          )
          KeyedList.Entry("Platforms") {
            InlineList(template.configuration.platforms ?? ["all"])
          }
          KeyedList.Entry(
            "Visibility",
            (template.configuration.visibility ?? .public).rawValue
          )
        }
      }
      Section("Using this template") {
        ExampleCommand(exampleCommand)
      }
    }.show()
  }
}
