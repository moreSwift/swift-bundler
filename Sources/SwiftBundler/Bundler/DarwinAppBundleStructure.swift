import Foundation

/// The file/directory structure of a particular app bundle on disk.
struct DarwinAppBundleStructure {
  let contentsDirectory: URL
  let resourcesDirectory: URL
  let librariesDirectory: URL
  let frameworksDirectory: URL
  let executableDirectory: URL
  let infoPlistFile: URL
  let pkgInfoFile: URL
  let provisioningProfileFile: URL
  let appIconFile: URL
  let mainExecutable: URL

  /// Describes the structure of an app bundle for the specific platform. Doesn't
  /// create anything on disk (see ``DarwinAppBundleStructure/createDirectories()``).
  init(at bundleDirectory: URL, platform: ApplePlatform, appName: String) {
    let os = platform.os
    switch os {
      case .macOS:
        contentsDirectory = bundleDirectory / "Contents"
        executableDirectory = contentsDirectory / "MacOS"
        resourcesDirectory = contentsDirectory / "Resources"
      case .iOS, .tvOS, .visionOS:
        contentsDirectory = bundleDirectory
        executableDirectory = contentsDirectory
        resourcesDirectory = contentsDirectory
    }

    librariesDirectory = contentsDirectory / "Libraries"
    frameworksDirectory = contentsDirectory / "Frameworks"

    infoPlistFile = contentsDirectory / "Info.plist"
    pkgInfoFile = contentsDirectory / "PkgInfo"
    provisioningProfileFile = contentsDirectory / "embedded.mobileprovision"
    appIconFile = resourcesDirectory / "AppIcon.icns"

    mainExecutable = executableDirectory / appName
  }

  /// Attempts to create all directories within the app bundle. Ignores directories which
  /// already exist.
  func createDirectories() throws(DarwinBundler.Error) {
    let directories = [
      contentsDirectory, resourcesDirectory, librariesDirectory,
      frameworksDirectory, executableDirectory,
    ]

    for directory in directories where !directory.exists(withType: .directory) {
      do {
        try FileManager.default.createDirectory(at: directory)
      } catch {
        throw DarwinBundler.Error(.failedToCreateAppBundleDirectoryStructure)
      }
    }
  }
}
