import ArgumentParser
import Foundation

/// The subcommand for adding template repositories.
struct TemplateRepoAddCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "add",
    abstract: "Add a template repository to Swift Bundler.",
    usage: """
      swift-bundler template repo add <name> --path <path-to-repo>
      swift-bundler template repo add <name> --git <remote-git-url>
      """,
    discussion: """
      Repositories can either be remote or local; --git adds a remote \
      repository, and --path adds a local repository.
      """
  )

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages."
  )
  public var verbose = false

  @Argument(
    help: "The name for the template repository."
  )
  public var name: TemplateRepository.Name

  @Option(
    help: "A URL to a remote git repository",
    transform: { url in
      guard let parsed = URL(string: url) else {
        throw SwiftBundlerError.commandLineValidationError("--git requires a valid URL")
      }
      return parsed
    }
  )
  public var git: URL?

  @Option(
    help: "A path to a local repository."
  )
  public var path: String?

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    let source: URL
    let kind: TemplateRepository.Kind
    if let git, path == nil {
      source = git
      kind = .remoteGit
    } else if let path, git == nil {
      source = URL(fileURLWithPath: path)
      kind = .local
    } else {
      throw RichError(SwiftBundlerError.commandLineValidationError(
        "Must provide exactly one of --git or --path"
      ))
    }

    try await RichError<SwiftBundlerError>.catch {
      try await TemplateRepositoryManager.addTemplateRepository(
        name: name,
        source: source,
        kind: kind
      )
    }
  }
}
