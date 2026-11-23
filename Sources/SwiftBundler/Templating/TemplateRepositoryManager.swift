import Crypto
import Foundation

/// A utility for managing Swift Bundler template repositories.
enum TemplateRepositoryManager {
  /// The default template repository.
  static let defaultTemplateRepository =
    URL(string: "https://github.com/moreSwift/swift-bundler-templates")!

  /// Resolves a template repository from a given URL. The URL may be a remote
  /// Git repository URL, a local directory path, or `nil` if the default
  /// repository is to be used.
  ///
  /// Guarantees that the template repository is up-to-date.
  /// - Parameters:
  ///   - url: The template repository to resolve.
  ///   - autoUpdate: Whether to auto update the repository if it's already checked out.
  /// - Returns: A template repository.
  static func resolveTemplateRepository(
    url: URL?,
    autoUpdate: Bool = true
  ) async throws(Error) -> TemplateRepository {
    let url = url ?? defaultTemplateRepository
    guard !url.isFileURL else {
      return TemplateRepository(
        source: url,
        checkout: url
      )
    }

    let checkout = try await checkoutDirectory(for: url)
    if autoUpdate {
      try await ensureUpToDateCheckout(of: url, at: checkout)
    } else {
      try await ensureCheckout(of: url, at: checkout)
    }
    return TemplateRepository(
      source: url,
      checkout: checkout
    )
  }

  /// Ensures that a checkout of `repository` exists at `checkout`.
  /// - Parameters:
  ///   - repository: The remote repository.
  ///   - checkout: The local checkout.
  private static func ensureCheckout(
    of repository: URL,
    at checkout: URL
  ) async throws(Error) {
    if !checkout.exists(withType: .directory) {
      try await Error.catch {
        try await Git.clone(repository, to: checkout)
      }
    }
  }

  /// Ensures that a checkout of `repository` exists at `checkout` and is up-to-date.
  /// - Parameters:
  ///   - repository: The remote repository.
  ///   - checkout: The local checkout.
  private static func ensureUpToDateCheckout(
    of repository: URL,
    at checkout: URL
  ) async throws(Error) {
    try await ensureCheckout(of: repository, at: checkout)

    do {
      try await Git.fetch(checkout)
      try await Git.checkout(checkout, revision: "v\(SwiftBundler.version.major)")
      try await Git.pull(checkout)
    } catch {
      throw Error(.failedToPullLatestTemplates(checkout), cause: error)
    }
  }

  /// Gets the directory to check out a particular remote repository to.
  private static func checkoutDirectory(for repository: URL) async throws(Error) -> URL {
    let parent = try await getTemplateRepositoriesDirectory()
    let uniqueValue = repository.absoluteString
    let digest = SHA256.hash(data: Data(uniqueValue.utf8)).hex()

    // The digest makes checkout paths unique even if two repositories share the same name
    let name = repository.lastPathComponent + "-" + digest
    return parent / name
  }

  /// Gets the directory that Swift Bundler checks out template repositories to.
  private static func getTemplateRepositoriesDirectory() async throws(Error) -> URL {
    try Error.catch {
      try System.getApplicationSupportDirectory()
    } / "template-repositories"
  }
}
