import ArgumentParser
import Foundation

/// The subcommand for listing available template repositories.
struct TemplateRepoListCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "ls",
    abstract: "List available template repositories."
  )

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages."
  )
  public var verbose = false

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    let repositories = try await RichError<SwiftBundlerError>.catch {
      try await TemplateRepositoryManager.enumerateRepositories()
    }

    Output {
      KeyedList {
        for repository in repositories {
          let source = repository.source.isFileURL
            ? repository.source.path
            : repository.source.absoluteString
          KeyedList.Entry(repository.name.description, source)
        }
      }
    }.show()
  }
}
