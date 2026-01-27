import ErrorKit
import Foundation

extension Java {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``Java``.
  enum ErrorMessage: Throwable {
    case invalidJavaHome(URL, executable: URL)
    case javaNotFound

    var userFriendlyMessage: String {
      switch self {
        case .invalidJavaHome(let javaHome, let executable):
          let executablePath = executable.path(relativeTo: javaHome)
          return """
            $JAVA_HOME is set to an invalid directory '\(javaHome.path)'; execpted \
            to find java executable at '\(executablePath)'
            """
        case .javaNotFound:
          return """
            Could not locate java executable; java not found on $PATH, and \
            $JAVA_HOME not set
            """
      }
    }
  }
}
