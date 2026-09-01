import Foundation

/// A basic error emitted by mocks.
struct MockError: LocalizedError {
  var message: String

  var errorDescription: String? {
    message
  }

  init(_ message: String) {
    self.message = message
  }
}
