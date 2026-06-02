import Foundation
import Version

/// A utility that wraps the WiX CLI (used to create Windows MSIs).
enum WiXTool {
  /// The base WiX download URL. Append a semantic version to get the actual download URL.
  static let wixBaseDownloadURL = URL(
    string: "https://www.nuget.org/api/v2/package/wix"
  )!

  /// The WiX CLI version that Swift Bundler uses.
  static let wixCLIVersion = Version(6, 0, 0)

  /// Builds the WiX package described by the given WXS file.
  /// - Parameter workspaceRoot: The directory that extensions are installed in.
  ///   Should generally be whatever the user perceives as their current project's
  ///   root directory so that they can easily run failing wix commands themselves
  ///   to debug issues.
  static func build(
    wxsFile: URL,
    sourceDirectory: URL,
    outputLocation: URL,
    architecture: BuildArchitecture,
    workspaceRoot: URL,
    extensions: [String]
  ) async throws(Error) {
    let wixCLI = try await Error.catch {
      try await WiXTool.ensureWiXCLI(version: wixCLIVersion)
    }

    try await Error.catch {
      try await Process.create(
        wixCLI.path,
        arguments: [
          "build",
          "-b", sourceDirectory.path,
          "-o", outputLocation.path,
          "-arch", architecture.wixName,
          wxsFile.path,
        ] + extensions.flatMap { ["-ext", $0] },
        runSilentlyWhenNotVerbose: false
      ).runAndWait()
    }
  }

  /// A WiX extension specifier. Encoded as '<identifier>/<specifier>'
  /// (e.g. 'WixToolset.Util.wixext/6.0.0').
  struct ExtensionSpecifier: CustomStringConvertible, Hashable, Sendable,
    Codable, TriviallyFlattenable
  {
    var identifier: String
    var version: Version

    var description: String {
      "\(identifier)/\(version)"
    }

    init(parsing specifier: String) throws(Error) {
      let parts = specifier.split(
        separator: "/",
        maxSplits: 1,
        omittingEmptySubsequences: false
      )

      guard parts.count == 2 else {
        throw Error(.invalidExtensionSpecifier(specifier))
      }

      identifier = String(parts[0])
      let versionString = String(parts[1])
      guard let version = Version(tolerant: versionString) else {
        throw Error(.invalidExtensionVersion(identifier, versionString))
      }
      self.version = version
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      try self.init(parsing: value)
    }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(description)
    }
  }

  /// Ensures that a requested set of WiX extensions is available in the current
  /// workspace.
  static func ensureExtensions(
    _ extensions: [ExtensionSpecifier],
    workspaceRoot: URL
  ) async throws(Error) {
    guard !extensions.isEmpty else {
      return
    }

    let installedExtensions = try await listExtensions(workspaceRoot: workspaceRoot)
    for requestedExtension in extensions {
      guard !installedExtensions.contains(requestedExtension) else { continue }
      log.info("Installing WiX extension \(requestedExtension)")
      try await installExtension(requestedExtension, workspaceRoot: workspaceRoot)
    }
  }

  /// Lists available extensions in the current workspace.
  static func listExtensions(
    workspaceRoot: URL
  ) async throws(Error) -> [ExtensionSpecifier] {
    let wixCLI = try await Error.catch {
      try await WiXTool.ensureWiXCLI(version: wixCLIVersion)
    }

    let output = try await Error.catch {
      do {
        return try await Process.create(
          wixCLI.path,
          arguments: [
            "extension",
            "list"
          ],
          directory: workspaceRoot
        ).getOutput()
      } catch let error as Process.Error {
        // 'wix extension list' exits with the status code '2' when there aren't
        // any extensions to list.
        switch error.message {
          case .nonZeroExitStatusWithOutput(let output, _, 2):
            if output.isEmpty {
              return ""
            } else {
              throw error
            }
          default:
            throw error
        }
      }
    }.trimmingCharacters(in: .whitespacesAndNewlines)

    let lines = output.split(separator: "\n").map { line in
      String(line.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    return try lines.map { line throws(Error) in
      try ExtensionSpecifier(parsing: line)
    }
  }

  /// Installs the given WiX extension.
  /// - Parameter workspaceRoot: The directory that extensions are installed in.
  ///   Should generally be whatever the user perceives as their current project's
  ///   root directory so that they can easily run failing wix commands themselves
  ///   to debug issues.
  static func installExtension(
    _ specifier: ExtensionSpecifier,
    workspaceRoot: URL
  ) async throws(Error) {
    let wixCLI = try await Error.catch {
      try await WiXTool.ensureWiXCLI(version: wixCLIVersion)
    }

    try await Error.catch {
      try await Process.create(
        wixCLI.path,
        arguments: [
          "extension",
          "add",
          specifier.description
        ],
        directory: workspaceRoot
      ).runAndWait()
    }
  }

  /// Ensures that Swift Bundler has specified version of the WiX CLI available.
  /// Attempts to download the CLI if it's not available.
  /// - Returns: The location of Swift Bundler's WiX CLI (with the specified version)
  ///   on disk.
  static func ensureWiXCLI(version: Version) async throws(Error) -> URL {
    let toolsDirectory = try Error.catch {
      try System.getToolsDirectory()
    }

    let wixInstallDirectory = toolsDirectory / "wix-\(version)"
    let wix = wixInstallDirectory / "wix.exe"
    if wix.exists() {
      return wix
    }

    let wixDownloadURL = wixBaseDownloadURL / version.description
    log.info("Downloading WiX")
    log.debug("Downloading WiX from \(wixDownloadURL.absoluteString)")
    let uuid = UUID().uuidString
    let temp = FileManager.default.temporaryDirectory
    let wixZip = temp / "wix-\(uuid).zip"
    let wixDirectory = temp / "wix-\(uuid)"
    try Error.catch(withMessage: .failedToDownloadWiXCLI) {
      let content = try Data(contentsOf: wixDownloadURL)
      try content.write(to: wixZip)
      try FileManager.default.unzipItem(at: wixZip, to: wixDirectory)
    }

    defer {
      try? FileManager.default.removeItem(at: wixZip)
    }

    // Locate the subdirectory containing the tool itself
    let subdirectory = try Error.catch {
      let packageToolsDirectory = wixDirectory / "tools"
      let contents = try FileManager.default.contentsOfDirectory(at: packageToolsDirectory)
        .map(\.lastPathComponent)
      if contents.contains("net8.0") {
        return packageToolsDirectory / "net8.0"
      } else {
        // Stably guess a subdirectory. If net8.0 doesn't exist, we hope to find
        // a newer version of the net subdirectory.
        let contents = contents.sorted()
        if let directory = contents.first(where: { $0.hasPrefix("net") }) {
          return packageToolsDirectory / directory
        } else if let directory = contents.first {
          return packageToolsDirectory / directory
        }
      }

      throw Error(.failedToLocateWiXCLI(directory: wixDirectory, guess: nil))
    } / "any"

    let guess = subdirectory / "wix.exe"
    guard guess.exists() else {
      throw Error(.failedToLocateWiXCLI(directory: wixDirectory, guess: guess))
    }

    try Error.catch {
      try FileManager.default.copyItem(
        at: subdirectory,
        to: wixInstallDirectory
      )
    }
    
    // Only remove the directory if we successfully locate the executable, to make
    // debugging a little easier
    try? FileManager.default.removeItem(at: wixDirectory)

    return wix
  }
}
