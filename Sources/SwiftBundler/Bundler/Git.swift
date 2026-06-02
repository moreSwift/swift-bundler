import Foundation

enum Git {
  static func clone(_ remote: URL, to destination: URL) async throws(Error) {
    do {
      try await Process.create(
        "git",
        arguments: [
          "clone",
          "--recursive",
          remote.absoluteString,
          destination.path,
        ],
        runSilentlyWhenNotVerbose: false
      ).runAndWait()
    } catch {
      throw Error(
        .failedToCloneRepository(remote, destination: destination),
        cause: error
      )
    }
  }

  static func getRemoteURL(_ repository: URL, remote: String) async throws(Error) -> URL {
    do {
      let output = try await Error.catch {
        try await Process.create(
          "git",
          arguments: [
            "remote",
            "get-url",
            remote,
          ],
          directory: repository
        ).getOutput()
      }

      let url = output.trimmingCharacters(in: .whitespacesAndNewlines)

      guard let url = URL(string: url) else {
        throw Error(.invalidRemoteURL(url))
      }

      return url
    } catch {
      throw Error(.failedToGetRemoteURL(repository, remote: remote), cause: error)
    }
  }

  static func getCommitHash(
    _ repository: URL,
    of revision: String = "HEAD"
  ) async throws(Error) -> String {
    do {
      return try await Process.create(
        "git",
        arguments: ["rev-parse", revision],
        directory: repository
      ).getOutput().trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      throw Error(.failedToGetCommitHash(repository, revision), cause: error)
    }
  }

  static func countRevisions(
    _ repository: URL,
    at revision: String = "HEAD"
  ) async throws(Error) -> Int {
    let digits: String
    do {
      digits = try await Process.create(
        "git",
        arguments: ["rev-list", "--count", revision],
        directory: repository
      ).getOutput(excludeStdError: true).trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      throw Error(.failedToCountRevisions(repository, revision), cause: error)
    }

    guard let count = Int(digits) else {
      throw Error(.failedToCountRevisions(repository, revision))
    }

    return count
  }
}
