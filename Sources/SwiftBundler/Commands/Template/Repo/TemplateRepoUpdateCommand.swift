import ArgumentParser
import Foundation

/// The subcommand for updating template repositories.
struct TemplateRepoUpdateCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "update",
    abstract: "Update templates repositories."
  )

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages."
  )
  public var verbose = false

  @Flag(
    name: .shortAndLong,
    help: "Update all template repositories."
  )
  public var all = false

  @Argument(
    help: "A specific template repository to update."
  )
  public var repository: TemplateRepository.Name?

  func wrappedValidate() throws(RichError<SwiftBundlerError>) {
    if all != (repository == nil) {
      throw RichError(SwiftBundlerError.commandLineValidationError(
        "Must provide exactly one of --all or <repository>"
      ))
    }
  }

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    let elapsed = try await RichError<SwiftBundlerError>.catch {
      try await Stopwatch.time {
        if let repository {
          let repo = try await TemplateRepositoryManager.resolveTemplateRepository(
            name: repository
          )
          if repo.kind == .local {
            log.warning("'\(repository)' is a local repository; nothing to do")
          }
        } else {
          let repositories = try await TemplateRepositoryManager.enumerateRepositories()
          for repository in repositories {
            try await TemplateRepositoryManager.updateRepository(repository)
          }
        }
      }
    }

    log.info("Done in \(elapsed.secondsString).")
  }
}
