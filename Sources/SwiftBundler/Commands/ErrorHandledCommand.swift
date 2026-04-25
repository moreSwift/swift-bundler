import ArgumentParser
import Foundation
import ErrorKit

/// An extension to the `AsyncParsableCommand` API with custom error handling.
///
/// Ideally this would be generic over the error type, but that causes a compiler
/// crash under Swift 6.2 on Windows.
protocol ErrorHandledCommand: AsyncParsableCommand {
  var verbose: Bool { get }

  /// Implement this instead of `validate()` to get custom Swift Bundler error handling.
  func wrappedValidate() throws(RichError<SwiftBundlerError>)

  /// Implement this instead of `run()` to get custom Swift Bundler error handling.
  func wrappedRun() async throws(RichError<SwiftBundlerError>)
}

extension ErrorHandledCommand {
  func wrappedValidate() throws(RichError<SwiftBundlerError>) {}
}

extension ErrorHandledCommand {
  func validate() {
    if verbose {
      log.logLevel = .debug
    }

    do {
      try wrappedValidate()
    } catch {
      displayError(error, verbose: verbose, displayHints: true)
      Foundation.exit(1)
    }
  }

  func run() async {
    do {
      try await wrappedRun()
    } catch {
      displayError(error, verbose: verbose, displayHints: true)
      Foundation.exit(1)
    }
  }
}
