import Foundation

/// A utility for interacting with java.
enum Java {
  /// Locates the user's configured Java executable.
  static func locateJavaExecutable() async throws(Error) -> URL {
    // Logic adapted from gradlew shell script
    if let javaHomePath = ProcessInfo.processInfo.environment["JAVA_HOME"] {
      let javaHome = URL(fileURLWithPath: javaHomePath)

      // IBM's JDK on AIX uses strange locations for the executables
      let strangeLocation = javaHome / "jre/sh/java"
      if strangeLocation.exists() {
        return strangeLocation
      }

      let location = javaHome / "bin/java"
      guard location.exists() else {
        throw Error(.invalidJavaHome(javaHome, executable: location))
      }

      return location
    } else {
      let location = try await Error.catch(withMessage: .javaNotFound) {
        try await Process.locate("java")
      }
      return URL(fileURLWithPath: location)
    }
  }
}
