import ErrorKit

extension TOMLValue {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``TOMLValue``.
  enum ErrorMessage: Throwable {
    case failedToDecodeTOMLValue(CodingPath)

    var userFriendlyMessage: String {
      switch self {
        case .failedToDecodeTOMLValue(let path):
          return """
            Failed to decode TOML value at \(path.description) as its type was \
            not handled by TOMLValue; please file an issue at \(SwiftBundler.newIssueURL)
            """
      }
    }
  }
}
