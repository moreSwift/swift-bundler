import Foundation

extension SwiftPackageManager {
  /// Loads a package's package manifest via the 'swift package dump-package'
  /// command. It only loads precisely the information required by other Swift
  /// Bundler methods in order to minimise the risk of a future format changing
  /// breaking Swift Bundler. It also attempts to return a partial result when it
  /// encounters unexpected data, rather than failing entirely, leading to more
  /// graceful degradation when broken by a format change or edge case.
  static func loadPartialPackageDump(
    packageDirectory: URL,
    toolchain: URL?
  ) async throws(Error) -> PartialPackageDump {
    let process = Process.create(
      swiftPath(toolchain: toolchain),
      arguments: ["package", "dump-package"],
      directory: packageDirectory
    )

    let output = try await Error.catch {
      try await process.getOutputData(excludeStdError: true)
    }

    return try Error.catch {
      try JSONDecoder().decode(PartialPackageDump.self, from: output)
    }
  }
}
