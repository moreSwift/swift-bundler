import Crypto
import ErrorKit
import Foundation

/// A utility for managing Swift Bundler template repositories.
///
/// The manager keeps track of the template repositories that it manages using
/// a template repository index file. The index file is stored at
/// ``TemplateRepositoryManager/indexPath`` within Swift Bundler's application
/// support directory.
enum TemplateRepositoryManager {
  /// The default template repository's remote URL.
  private static let defaultTemplateRepositoryURL =
    URL(string: "https://github.com/moreSwift/swift-bundler-templates")!

  /// The path of the template repository index within Swift Bundler's application
  /// support directory.
  private static let indexPath = "template-repositories.json"

  /// Resolves a template repository from a given URL. The URL may be a remote
  /// Git repository URL, a local directory path, or `nil` if the default
  /// repository is to be used.
  ///
  /// Guarantees that the template repository is up-to-date.
  /// - Parameters:
  ///   - url: The template repository to resolve.
  ///   - autoUpdate: Whether to auto update the repository if it's already checked out.
  ///   - showAutoUpdateHint: If `true`, shows a hint about how to disable auto-updates
  ///     when a repository gets auto-updated. Defaults to true.
  /// - Returns: A template repository.
  static func resolveTemplateRepository(
    name: TemplateRepository.Name,
    autoUpdate: Bool = true,
    showAutoUpdateHint: Bool = true
  ) async throws(Error) -> TemplateRepository {
    let index = try await loadIndex()
    guard
      let repository = index.repositories.first(where: { repository in
        repository.name == name
      })
    else {
      throw Error(
        .noSuchRepository(name),
        hint: "Run `swift-bundler template repo ls` to list available template repositories"
      )
    }

    try await ensureCheckout(
      of: repository,
      autoUpdate: autoUpdate,
      showAutoUpdateHint: showAutoUpdateHint
    )

    return repository
  }

  /// The reason that a repository doesn't support updates.
  enum ReasonRepositoryLacksUpdateSupport {
    case isLocal
  }

  /// Checks whether a repository lacks support for updates.
  static func repositoryLacksUpdateSupport(
    _ repository: TemplateRepository
  ) -> ReasonRepositoryLacksUpdateSupport? {
    switch repository.kind {
      case .remoteGit:
        return nil
      case .local:
        return .isLocal
    }
  }

  /// Add a new template repository to the index, and create a checkout if necessary.
  /// - Parameters:
  ///   - name: The name for the repository.
  ///   - source: The repository's source. A remote git URL for
  ///     ``TemplateRepository/Kind/remoteGit``, and a local file URL for
  ///     ``TemplateRepository/Kind/local``.
  ///   - kind: The kind of template repository (e.g. remote git or local).
  static func addTemplateRepository(
    name: TemplateRepository.Name,
    source: URL,
    kind: TemplateRepository.Kind
  ) async throws(Error) {
    var index = try await loadIndex()
    guard !index.repositories.lazy.map(\.name).contains(name) else {
      throw Error(
        .repositoryNameNotUnique(name),
        hint: "Run `swift-bundler template repo ls` to list existing template repositories"
      )
    }

    let repository = TemplateRepository(
      name: name,
      source: source,
      checkout: kind == .remoteGit
        ? try checkoutDirectory(for: name)
        : source,
      kind: kind
    )
    if kind == .remoteGit {
      try await ensureCheckout(
        of: repository,
        autoUpdate: false,
        showAutoUpdateHint: false
      )
    }

    index.repositories.append(repository)
    try saveIndex(index)
  }

  /// Removes a template repository from the index, and deletes its checkout if safe.
  /// - Parameters:
  ///   - name: The name of the repository to remove.
  static func removeTemplateRepository(
    name: TemplateRepository.Name
  ) async throws(Error) {
    var index = try await loadIndex()
    let matches = index.repositories.filter { repository in
      repository.name == name
    }

    guard matches.count > 0 else {
      throw Error(
        .noSuchRepository(name),
        hint: "Run `swift-bundler template repo ls` to list existing template repositories"
      )
    }

    if matches.count > 1 {
      log.warning(
        "Found multiple repositories with the same name; the index may have been corrupted"
      )
    }

    let templateRepositoryDirectory = try getTemplateRepositoriesDirectory()
    for match in matches {
      // Only delete checkouts of remote template repositories, and only those
      // that are in our managed templates directory (in case someone has
      // tampered with the template repository index to point at their own
      // managed checkout)
      guard
        match.isRemote,
        match.checkout.isContained(in: templateRepositoryDirectory)
      else {
        continue
      }

      try Error.catch {
        try FileManager.default.removeItem(at: match.checkout)
      }
    }

    index.repositories.removeAll { repository in
      repository.name == name
    }

    try saveIndex(index)
  }

  /// Resolves a template from its name. If a repository is specified then only
  /// templates within that repository are considered. Otherwise all repositories
  /// are checked.
  static func resolveTemplate(
    name: Template.Name,
    repository: TemplateRepository.Name?,
    autoUpdate: Bool = true
  ) async throws(Error) -> Template {
    let repositories: [TemplateRepository]
    if let repository {
      repositories = [
        try await Error.catch {
          try await TemplateRepositoryManager
            .resolveTemplateRepository(name: repository, autoUpdate: autoUpdate)
        }
      ]
    } else {
      repositories = try await enumerateRepositories()
      for repository in repositories {
        try await ensureCheckout(of: repository, autoUpdate: autoUpdate)
      }
    }

    let candidates = try repositories.flatMap { (repository) throws(Error) in
      try repository.enumerateTemplates()
        .map { (repo: repository.name, template: $0.value) }
    }

    let matchingTemplates = candidates.filter { candidate in
      candidate.template.name == name
    }
    guard let template = matchingTemplates.first else {
      throw Error(
        .noSuchTemplate(name),
        hint: "Run `swift-bundler template ls` to list available templates"
      )
    }

    if matchingTemplates.count > 1 {
      throw RichError(
        .ambiguousTemplateName(
          name,
          matchingTemplates.sorted {
            $0.template.repository.name.name < $1.template.repository.name.name
          }
        ),
        hint: "Use `--repo [repo_name]` to disambiguate"
      )
    }

    return template.template
  }

  /// Enumerates all repositories in the manager's index.
  /// - Returns: All repositories in the manager's index.
  static func enumerateRepositories() async throws(Error) -> [TemplateRepository] {
    return try await loadIndex().repositories
  }

  /// Updates a repository's checkout if it's a remote repository. Checks out the
  /// repository if no checkout is present.
  /// - Parameter repository: The repository to update.
  static func updateRepository(_ repository: TemplateRepository) async throws(Error) {
    try await ensureCheckout(of: repository, autoUpdate: true, showAutoUpdateHint: false)
  }

  /// Ensures that a checkout of `repository` exists at its designated checkout
  /// location. This is a no-op for local repositories.
  /// - Parameters:
  ///   - repository: The repository.
  ///   - autoUpdate: If `true`, existing checkouts will get updated.
  ///   - showAutoUpdateHint: If `true`, shows a hint about how to disable auto-updates
  ///     when a repository gets auto-updated. Defaults to true.
  static func ensureCheckout(
    of repository: TemplateRepository,
    autoUpdate: Bool,
    showAutoUpdateHint: Bool = true
  ) async throws(Error) {
    if repository.kind == .remoteGit {
      let alreadyExisted = repository.checkout.exists(withType: .directory)
      if !alreadyExisted {
        try await Error.catch {
          try await Git.clone(repository.source, to: repository.checkout)
        }
      }

      if autoUpdate || !alreadyExisted {
        if alreadyExisted && showAutoUpdateHint {
          log.info(
            """
            Updating '\(repository.name)'; use SBUN_AUTO_UPDATE_TEMPLATES=0 \
            to disable auto-updates
            """
          )
        }
        try await updateCheckout(at: repository.checkout)
      }
    }
  }

  /// Ensures that a template repository checkout is up-to-date.
  /// - Parameters:
  ///   - checkout: The local checkout.
  private static func updateCheckout(
    at checkout: URL
  ) async throws(Error) {
    do {
      try await Git.fetch(checkout)
      try await Git.checkout(checkout, revision: "v\(SwiftBundler.version.major)")
      try await Git.pull(checkout)
    } catch {
      throw Error(.failedToPullLatestTemplates(checkout), cause: error)
    }
  }

  /// Gets the directory to check out a particular remote repository to.
  private static func checkoutDirectory(
    for repositoryName: TemplateRepository.Name
  ) throws(Error) -> URL {
    let parent = try getTemplateRepositoriesDirectory()
    return parent / repositoryName.name
  }

  /// Gets the directory that Swift Bundler checks out template repositories to.
  private static func getTemplateRepositoriesDirectory() throws(Error) -> URL {
    try Error.catch {
      try System.getApplicationSupportDirectory()
    } / "template-repositories"
  }

  // MARK: Index helpers

  /// Gets the location of Swift Bundler's template repository index file.
  private static func templateRepositoryIndexFile() throws(Error) -> URL {
    try Error.catch {
      try System.getApplicationSupportDirectory()
    } / indexPath
  }

  /// Loads the template repository index from Swift Bundler's application support directory.
  /// - Returns: The index. If an index didn't exist or is invalid, a default one
  ///   gets synthesized.
  private static func loadIndex() async throws(Error) -> TemplateRepositoryIndex {
    let indexFile = try templateRepositoryIndexFile()
    guard indexFile.exists() else {
      return try await createDefaultTemplateRepositoryIndex()
    }

    let data = try Error.catch {
      try Data(contentsOf: indexFile)
    }

    let index: TemplateRepositoryIndex
    do {
      index = try JSONDecoder().decode(TemplateRepositoryIndex.self, from: data)
    } catch {
      log.warning("\(ErrorKit.userFriendlyMessage(for: error))")
      log.warning("Existing template repository index is corrupted; resetting to default")
      return try await createDefaultTemplateRepositoryIndex()
    }

    guard index.schema == TemplateRepositoryIndex.currentSchema else {
      log.warning(
        """
        Existing template repository index has an unsupported schema version \
        '\(index.schema)'; resetting to default
        """
      )
      return try await createDefaultTemplateRepositoryIndex()
    }

    return index
  }

  /// Saves the template repository index to Swift Bundler's pplication support directory.
  /// - Parameter index: The index to save.
  private static func saveIndex(_ index: TemplateRepositoryIndex) throws(Error) {
    let indexFile = try templateRepositoryIndexFile()
    let data = try Error.catch {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
      return try encoder.encode(index)
    }
    try Error.catch {
      try data.write(to: indexFile)
    }
  }

  /// Creates a template repository index containing just the default repository,
  /// and saves the index to disk.
  private static func createDefaultTemplateRepositoryIndex()
    async throws(Error) -> TemplateRepositoryIndex
  {
    let name = TemplateRepository.Name.default
    let source = defaultTemplateRepositoryURL
    let index = TemplateRepositoryIndex(
      schema: TemplateRepositoryIndex.currentSchema,
      repositories: [
        TemplateRepository(
          name: name,
          source: source,
          checkout: try checkoutDirectory(for: name),
          kind: .remoteGit
        )
      ]
    )
    try saveIndex(index)
    return index
  }
}
