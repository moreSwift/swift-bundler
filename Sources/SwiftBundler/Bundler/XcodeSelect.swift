import Foundation

/// A wrapper for the xcode-select CLI.
enum XcodeSelect {
  /// Locates the user's Xcode developer directory.
  static func locateXcodeDeveloperDirectory() async throws(Error) -> URL {
    let output = try await Error.catch {
      try await Process.create(
        "xcode-select", arguments: ["-p"]
      ).getOutput().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let xcodeDeveloperDirectory = URL(fileURLWithPath: output)
    guard xcodeDeveloperDirectory.exists(withType: .directory) else {
      throw Error(.nonExistentDeveloperDirectory(xcodeDeveloperDirectory))
    }

    return xcodeDeveloperDirectory
  }

  /// Locates the user's Xcode toolchains directory.
  static func locateXcodeToolchainsDirectory() async throws(Error) -> URL? {
    let xcodeDeveloperDirectory = try await locateXcodeDeveloperDirectory()

    let toolchainsDirectory = xcodeDeveloperDirectory / "Toolchains"
    guard toolchainsDirectory.exists(withType: .directory) else {
      log.debug(
        """
        Xcode developer directory at '\(toolchainsDirectory.path)' doesn't \
        have a 'Toolchains' subdirectory. This probably means that it's a \
        CommandLineTools installation.
        """
      )
      return nil
    }

    return toolchainsDirectory
  }
}
