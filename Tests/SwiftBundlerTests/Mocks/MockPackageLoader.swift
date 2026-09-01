import Foundation
@testable import SwiftBundler

/// The default package loader used by ``SwiftPackageManager``.
///
/// Loads hardcoded packages provided at the time of initialization. Packages
/// are keyed by either an absolute path or a URL depending on whether they're
/// a local package or a remote git package.
struct MockPackageLoader: SwiftPackageManager.PackageLoader {
  typealias Package = SwiftPackageManager.Package<SwiftPackageManager.PackageDependency>

  var packages: [URL: Package]

  init(packages: [URL: Package]) {
    self.packages = packages
  }

  init(packages: [Package]) {
    self.packages = Dictionary(uniqueKeysWithValues: packages.map { package in
      (package.source.url, package)
    })
  }
  
  func prepare(
    packageDirectory: URL,
    toolchain: URL?
  ) async throws(SwiftPackageManager.Error) {}

  func loadPackage(
    packageDirectory: URL,
    source: SwiftPackageManager.PackageSource,
    identityOverride: String?,
    isRootPackage: Bool,
    configurationContext: ConfigurationFlattener.Context,
    toolchain: URL?
  ) async throws(SwiftPackageManager.Error)
    -> SwiftPackageManager.Package<SwiftPackageManager.PackageDependency>
  {
    let ident = source.url

    guard let package = packages[ident] else {
      throw SwiftPackageManager.Error(cause: MockError("No package at \(packageDirectory.path)"))
    }

    return package
  }
}
