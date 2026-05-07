import Foundation
import Version

enum WindowsManifestTool {
  /// Creates a Windows application manifest for a given executable file, using
  /// the provided values to fill in the minimal required fields, and optionally
  /// applying a user-provided manifest overlay.
  static func createApplicationManifest(
    at manifestFile: URL,
    for executable: URL,
    name: String,
    version: Version?,
    description: String?,
    architecture: BuildArchitecture,
    overlay: WindowsApplicationManifest?
  ) throws(Error) {
    let manifest = generateApplicationManifest(
      for: executable,
      name: name,
      version: version,
      description: description,
      architecture: architecture,
      overlay: overlay
    )

    let data = try Error.catch(
      withMessage: .failedToEncodeApplicationManifest(executable: executable)
    ) {
      try manifest.encode()
    }

    try Error.catch {
      try data.write(to: manifestFile)
    }
  }

  /// Generates the contents of a Windows application manifest, as per
  /// ``createApplicationManifest(at:for:name:version:architecture:overlay)``.
  static func generateApplicationManifest(
    for executable: URL,
    name: String,
    version: Version?,
    description: String?,
    architecture: BuildArchitecture,
    overlay: WindowsApplicationManifest?
  ) -> WindowsApplicationManifest {
    var manifest = overlay ?? WindowsApplicationManifest()
    manifest.manifestVersion ??= "1.0"
    manifest.description ??= description

    let version = version ?? Version(1, 0, 0)
    var assemblyIdentity = manifest.assemblyIdentity
      ?? WindowsApplicationManifest.AssemblyIdentity()
    assemblyIdentity.name ??= name
    assemblyIdentity.version ??= "\(version).0"
    assemblyIdentity.processorArchitecture ??= architecture.windowsApplicationManifestName
    assemblyIdentity.type ??= .win32
    manifest.assemblyIdentity = assemblyIdentity

    var file = manifest.file ?? WindowsApplicationManifest.File()
    file.name ??= executable.lastPathComponent
    manifest.file = file

    if var trustInfo = manifest.trustInfo {
      trustInfo.xmlns = WindowsApplicationManifest.TrustInfo.xmlns
      manifest.trustInfo = trustInfo
    }

    return manifest
  }

  /// Inserts an application manifest into an executable file using the 'mt'
  /// command line tool.
  static func insertApplicationManifest(
    _ manifest: URL,
    into executable: URL
  ) async throws(Error) {
    try await Error.catch {
      try await Process.create(
        "mt",
        arguments: [
          "-manifest", manifest.path,
          "-outputresource:\(executable.path);#1"
        ]
      ).runAndWait()
    }
  }
}

/// A convenience operator for applying default values in-place.
infix operator ??=

/// A convenience operator for applying default values in-place.
func ??=<T> (_ lhs: inout T?, _ rhs: @autoclosure () -> T?) {
  if lhs == nil {
    lhs = rhs()
  }
}
