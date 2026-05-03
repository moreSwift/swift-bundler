import ArgumentParser
import Foundation

/// The subcommand for listing available templates.
struct TemplatesListCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "list",
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
    name: .shortAndLong,
    help: "Print verbose error messages."
  )
  public var verbose = false

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    let templates: [Template] = try await RichError<SwiftBundlerError>.catch {
      let templateRepository = if let templateRepository {
        templateRepository
      } else {
        try await Templater.getDefaultTemplatesDirectory(downloadIfNecessary: true)
      }
      return try Templater.enumerateTemplates(in: templateRepository)
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
        ExampleCommand("swift bundler create [app-name] --template [template]" + repositoryOption)
      }
    }.show()
  }
}
