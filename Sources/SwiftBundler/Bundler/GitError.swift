import Foundation
import ErrorKit

extension Git {
  typealias Error = RichError<ErrorMessage>

  enum ErrorMessage: Throwable {
    case failedToCloneRepository(_ remote: URL, destination: URL)
    case failedToFetch(_ repository: URL)
    case failedToPull(_ repository: URL)
    case failedToCheckOutRevision(_ repository: URL, _ revision: String)
    case failedToGetRemoteURL(_ repository: URL, remote: String)
    case failedToGetCommitHash(_ repository: URL, _ revision: String)
    case failedToCountRevisions(_ repository: URL, _ revision: String)
    case invalidRemoteURL(String)

    var userFriendlyMessage: String {
      switch self {
        case .failedToCloneRepository(let remote, let destination):
          let destinationPath = destination.path(relativeTo: .currentDirectory)
          return "Failed to clone repository '\(remote)' to '\(destinationPath)'"
        case .failedToFetch(let repository):
          let repositoryPath = repository.path(relativeTo: .currentDirectory)
          return "Failed to fetch repository checked out at '\(repositoryPath)'"
        case .failedToPull(let repository):
          let repositoryPath = repository.path(relativeTo: .currentDirectory)
          return "Failed to pull repository checked out at '\(repositoryPath)'"
        case .failedToCheckOutRevision(let repository, let revision):
          let repositoryPath = repository.path(relativeTo: .currentDirectory)
          return """
            Failed to check out revision '\(revision)' in repository at \
            '\(repositoryPath)'
            """
        case .failedToGetRemoteURL(let repository, let remote):
          let repositoryPath = repository.path(relativeTo: .currentDirectory)
          return """
            Failed to get URL of remote '\(remote)' in local repository \
            '\(repositoryPath)'
            """
        case .failedToGetCommitHash(let repository, let revision):
          let repositoryPath = repository.path(relativeTo: .currentDirectory)
          return """
            Failed to get commit hash of \(revision) in local repository at \
            '\(repositoryPath)'
            """
        case .failedToCountRevisions(let repository, let revision):
          let repositoryPath = repository.path(relativeTo: .currentDirectory)
          return """
            Failed to count revisions up to and including \(revision) in local \
            repository at '\(repositoryPath)'
            """
        case .invalidRemoteURL(let url):
          return "Invalid remote URL '\(url)'"
      }
    }
  }
}
