import Foundation
import Version

/// A utility that wraps the NuGet CLI (and manages downloading/installing it).
enum NuGetTool {
  /// The URL that we download the NuGet CLI from. They only provide x86 builds,
  /// so we install the same executable no matter the host architecture and rely
  /// on Windows' built-in emulation.
  static let nugetDownloadURL = URL(
    string: "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
  )!

  /// Ensures that Swift Bundler's copy of the NuGet CLI is available. Attempts
  /// to download the CLI if it's not available.
  /// - Returns: The location of Swift Bundler's NuGet CLI on disk.
  static func ensureNuGetCLI() throws(Error) -> URL {
    let toolsDirectory = try Error.catch {
      try System.getToolsDirectory()
    }

    let nuget = toolsDirectory / "nuget.exe"
    if nuget.exists() {
      return nuget
    }

    log.info("Downloading NuGet")
    log.debug("Downloading NuGet from \(nugetDownloadURL.absoluteString)")
    try Error.catch(withMessage: .failedToDownloadNuGetCLI) {
      let content = try Data(contentsOf: nugetDownloadURL)
      try content.write(to: nuget)
    }

    return nuget
  }

  /// Installs a package in the given directory.
  static func installPackage(
    _ packageName: String,
    version: Version? = nil,
    in directory: URL
  ) async throws(Error) {
    var arguments = ["install", packageName]
    if let version {
      arguments += ["-Version", version.description]
    }

    try await Error.catch(withMessage: .failedToInstallPackage(packageName, version)) {
      try await Process.create(
        try ensureNuGetCLI().path,
        arguments: arguments,
        directory: directory
      ).runAndWait()
    }
  }
}
