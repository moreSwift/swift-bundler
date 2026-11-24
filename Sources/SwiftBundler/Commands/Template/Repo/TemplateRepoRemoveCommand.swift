import ArgumentParser
import Foundation

/// The subcommand for removing template repositories.
struct TemplateRepoRemoveCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "rm",
    abstract: "Removes a template repository from Swift Bundler.",
    discussion: """
      This command deletes the repository's checkout if an only if the \
      template repository's source is a remote git repository AND the checkout \
      is inside Swift Bundler's managed template repository checkout directory.
      """
  )

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages."
  )
  public var verbose = false

  @Argument(
    help: "The name of the template repository to remove."
  )
  public var name: TemplateRepository.Name

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    try await RichError<SwiftBundlerError>.catch {
      try await TemplateRepositoryManager.removeTemplateRepository(
        name: name
      )
    }
  }
}
