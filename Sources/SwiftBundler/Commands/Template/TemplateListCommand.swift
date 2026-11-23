import ArgumentParser
import Foundation

/// The subcommand for listing available templates.
struct TemplateListCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "ls",
    abstract: "List available templates."
  )

  /// The directory to search for templates in.
  @Option(
    name: .long,
    help: "An alternate directory to search for templates in.",
    transform: URL.init(fileURLWithPath:)
  )
  var templateRepository: URL?

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
    let templates = try await RichError<SwiftBundlerError>.catch {
      let templateRepository = try await TemplateRepositoryManager
        .resolveTemplateRepository(url: templateRepository, autoUpdate: shouldAutoUpdate)
      return try templateRepository.enumerateTemplates()
    }

    let repositoryOption: String
    if let templateRepository = templateRepository {
      repositoryOption =
        " --template-repository \(templateRepository.relativePath.quotedIfNecessary)"
    } else {
      repositoryOption = ""
    }

    Output {
      Section("Templates") {
        KeyedList {
          for template in templates {
            KeyedList.Entry(template.name, template.manifest.description)
          }
        }
      }
      Section("Using a template") {
        ExampleCommand("swift-bundler create [app-name] --template [template]" + repositoryOption)
      }
    }.show()
  }
}
