import ArgumentParser
import Foundation

/// The subcommand for updating the default templates repository.
struct TemplatesUpdateCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "update",
    abstract: "Update the default templates to the latest version."
  )

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages."
  )
  public var verbose = false

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    let elapsed = try await RichError<SwiftBundlerError>.catch {
      try await Stopwatch.time {
        try await Templater.updateTemplates()
      }
    }

    log.info("Done in \(elapsed.secondsString).")
  }
}
