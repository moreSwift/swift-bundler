import ArgumentParser
import Foundation

/// The subcommand for listing available templates.
struct TemplateListCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "ls",
    abstract: "List available templates."
  )

  @Option(
    name: [.customShort("r"), .customLong("repo")],
    help: "An template repository to list templates from."
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
    let templatesByRepository = try await RichError<SwiftBundlerError>.catch {
      if let templateRepository {
        let templateRepository = try await TemplateRepositoryManager
          .resolveTemplateRepository(
            name: templateRepository,
            autoUpdate: shouldAutoUpdate
          )
        return [(templateRepository.name, try templateRepository.enumerateTemplates())]
      } else {
        let templateRepositories = try await TemplateRepositoryManager.enumerateRepositories()
        for repository in templateRepositories {
          try await TemplateRepositoryManager.ensureCheckout(
            of: repository,
            autoUpdate: shouldAutoUpdate
          )
        }
        return try templateRepositories.map { repository throws(Error) in
          (repository.name, try repository.enumerateTemplates())
        }
      }
    }

    Output {
      for (repository, templates) in templatesByRepository {
        Section("\(repository.name)") {
          KeyedList {
            for template in templates {
              KeyedList.Entry(template.name, template.manifest.description)
            }
          }
        }
      }
      Section("Hint: Using a template") {
        ExampleCommand("swift-bundler create [app-name] --template [template]")
      }
    }.show()
  }
}
