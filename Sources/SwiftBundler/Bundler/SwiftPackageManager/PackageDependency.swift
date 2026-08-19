import Foundation

extension SwiftPackageManager {
  /// A package's dependency on another package.
  struct PackageDependency: Sendable, Codable {
    /// The target package.
    var package: PackageReference
    /// The traits enabled by this dependency edge.
    ///
    /// This doesn't necessarily include all traits that the target package
    /// ends up getting compiled with, because the final set of traits is the
    /// union of the traits enabled by all dependencies on a given target
    /// package.
    var traits: Set<String>
    /// The location of the dependency on disk.
    var location: PackageManifest.PackageDependency.Location

    /// Gets the path to the given dependency's local checkout. If the dependency
    /// is a local package dependency, then this returns the path to the
    /// dependency's source on disk.
    func localCheckout(packageDirectory: URL, checkoutsDirectory: URL) -> URL {
      switch location {
        case .fileSystem(let path):
          return path
        case .sourceControl(let location):
          var name = location.lastPathComponent
          let gitSuffix = ".git"
          if name.hasSuffix(gitSuffix) {
            name = String(name.dropLast(gitSuffix.count))
          }
          return checkoutsDirectory / name
      }
    }
  }
}

/// This implementation isn't involved in the initial decoding of a
/// ``PackageManifest``, only in subsequent encoding and decoding of a
/// ``SwiftPackageManager/Package``.
extension PackageManifest.PackageDependency.Location: Codable {
  enum CodingKeys: String, CodingKey {
    case localPath
    case remoteSourceControl
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if container.contains(.localPath) {
      let path = try container.decode(String.self, forKey: .localPath)
      self = .fileSystem(path: URL(fileURLWithPath: path))
    } else {
      let location = try container.decode(URL.self, forKey: .remoteSourceControl)
      self = .sourceControl(url: location)
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
      case .fileSystem(let url):
        try container.encode(url.path, forKey: .localPath)
      case .sourceControl(let url):
        try container.encode(url, forKey: .remoteSourceControl)
    }
  }
}
