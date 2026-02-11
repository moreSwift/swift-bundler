import ErrorKit

extension SimulatorManager {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``SimulatorManager``.
  enum ErrorMessage: Throwable {
    case failedToLocateSimulator([SimulatorOS]?, String)

    var userFriendlyMessage: String {
      switch self {
        case .failedToLocateSimulator(let oses, let searchTerm):
          if let oses {
            return """
              Failed to locate simulator matching search term '\(searchTerm)' for os in \(oses.map(\.displayName))
              """
          } else {
            return "Failed to locate simulator matching search term '\(searchTerm)'"
          }
      }
    }
  }
}
