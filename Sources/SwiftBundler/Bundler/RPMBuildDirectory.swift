import Foundation
import Version

extension RPMBundler {
  /// The structure of an `rpmbuild` directory.
  struct RPMBuildDirectory {
    /// The root directory of the structure.
    var root: URL
    var build: URL
    var buildRoot: URL
    var rpms: URL
    var sources: URL
    /// The app's `.tar.gz` source archive.
    var appSourceArchive: URL
    var specs: URL
    /// The app's RPM `.spec` file.
    var appSpec: URL
    var srpms: URL

    /// All directories described by this structure.
    var directories: [URL] {
      [root, build, buildRoot, rpms, sources, specs, srpms]
    }

    /// Describes the structure of an `rpmbuild` directory. Doesn't create
    /// anything on disk (see ``RPMBuildDirectory/createDirectories()``).
    init(at root: URL, escapedAppName: String, appVersion: Version) {
      self.root = root
      build = root / "BUILD"
      buildRoot = root / "BUILDROOT"
      rpms = root / "RPMS"
      sources = root / "SOURCES"
      appSourceArchive = sources / "\(escapedAppName)-\(appVersion).tar.gz"
      specs = root / "SPECS"
      appSpec = specs / "\(escapedAppName).spec"
      srpms = root / "SRPMS"
    }

    /// Creates all directories described by this directory structure.
    func createDirectories() throws(RPMBundler.Error) {
      for directory in directories {
        try FileManager.default.createDirectory(
          at: directory,
          errorMessage: ErrorMessage.failedToCreateRPMBuildDirectory
        )
      }
    }
  }
}
