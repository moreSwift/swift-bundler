import ErrorKit

/// An error representing a failed invariant. We use this to keep invaraint
/// failures separate from errors. Invariant failures are generally a lot less
/// likely to be presented to users, so making an additional error enum case
/// for each invariant that we'd like to enforce would be a wast of time.
struct InvariantFailure: Throwable {
  var userFriendlyMessage: String

  init(_ message: String) {
    userFriendlyMessage = message
  }
}
