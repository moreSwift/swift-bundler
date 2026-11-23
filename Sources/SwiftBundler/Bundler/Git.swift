import Foundation

enum Git {
  private static func runGit(
    in directory: URL?,
    withArguments arguments: [String],
    throwing errorMessage: @autoclosure () -> ErrorMessage
  ) async throws(Error) {
    do {
      try await Process.create(
        "git",
        arguments: arguments,
        directory: directory,
        runSilentlyWhenNotVerbose: false
      ).runAndWait()
    } catch {
      throw Error(
        errorMessage(),
        cause: error
      )
    }
  }

  private static func getGitOutput(
    in directory: URL?,
    withArguments arguments: [String],
    throwing errorMessage: @autoclosure () -> ErrorMessage
  ) async throws(Error) -> String {
    do {
      return try await Process.create(
        "git",
        arguments: arguments,
        directory: directory,
        runSilentlyWhenNotVerbose: false
      ).getOutput(excludeStdError: true)
    } catch {
      throw Error(
        errorMessage(),
        cause: error
      )
    }
  }

  static func clone(_ remote: URL, to destination: URL) async throws(Error) {
    try await runGit(
      in: nil,
      withArguments: [
        "clone",
        "--recursive",
        remote.absoluteString,
        destination.path,
      ],
      throwing: .failedToCloneRepository(remote, destination: destination)
    )
  }

  static func fetch(_ directory: URL) async throws(Error) {
    try await runGit(
      in: directory,
      withArguments: ["fetch"],
      throwing: .failedToFetch(directory)
    )
  }

  static func pull(_ directory: URL) async throws(Error) {
    try await runGit(
      in: directory,
      withArguments: ["fetch"],
      throwing: .failedToPull(directory)
    )
  }

  static func checkout(_ directory: URL, revision: String) async throws(Error) {
    try await runGit(
      in: directory,
      withArguments: [
        "checkout",
        revision
      ],
      throwing: .failedToCheckOutRevision(directory, revision)
    )
  }

  static func getRemoteURL(_ directory: URL, remote: String) async throws(Error) -> URL {
    do {
      let output =  try await getGitOutput(
        in: directory,
        withArguments: ["remote", "get-url", remote],
        throwing: .failedToGetRemoteURL(directory, remote: remote)
      )

      let url = output.trimmingCharacters(in: .whitespacesAndNewlines)

      guard let url = URL(string: url) else {
        throw Error(.invalidRemoteURL(url))
      }

      return url
    } catch {
      throw Error(.failedToGetRemoteURL(directory, remote: remote), cause: error)
    }
  }

  static func getCommitHash(
    _ repository: URL,
    of revision: String = "HEAD"
  ) async throws(Error) -> String {
    return try await getGitOutput(
      in: repository,
      withArguments: ["rev-parse", revision],
      throwing: .failedToGetCommitHash(repository, revision)
    ).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func countRevisions(
    _ repository: URL,
    at revision: String = "HEAD"
  ) async throws(Error) -> Int {
    let digits = try await getGitOutput(
      in: repository,
      withArguments: ["rev-list", "--count", revision],
      throwing: .failedToCountRevisions(repository, revision)
    ).trimmingCharacters(in: .whitespacesAndNewlines)

    guard let count = Int(digits) else {
      throw Error(.failedToCountRevisions(repository, revision))
    }

    return count
  }
}
