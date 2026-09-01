import Foundation

extension SwiftPackageManager {
  /// A loader for Swift packages.
  protocol PackageLoader: Sendable {
    /// Prepares a package for package graph loading. This should perform any
    /// setup required to load both the package itself and all of its active
    /// dependencies. The default loader implements this by running
    /// `swift package resolve`.
    /// - Parameters:
    ///   - packageDirectory: The directory of the root package.
    ///   - toolchain: The Swift toolchain to use.
    func prepare(
      packageDirectory: URL,
      toolchain: URL?
    ) async throws(Error)

    /// Loads a package.
    /// - Parameters:
    ///   - packageDirectory: The root directory of the package to load.
    ///   - source: The original source of the package.
    ///   - identityOverride: The package's identity according to whichever package
    ///     is depending on this package (if any). If `nil` then the package's name
    ///     field is lowercased to obtain its identity according to itself.
    ///   - isRootPackage: Whether the package is the root package or not. If
    ///     not the root package, SwiftPM filters out certain products, and
    ///     implementations of this method should too.
    ///   - configurationContext: Context to use when loading Swift Bundler
    ///     configuration files from packages.
    ///   - toolchain: The Swift toolchain to use.
    /// - Returns: The package.
    func loadPackage(
      packageDirectory: URL,
      source: PackageSource,
      identityOverride: String?,
      isRootPackage: Bool,
      configurationContext: ConfigurationFlattener.Context,
      toolchain: URL?
    ) async throws(Error) -> Package<PackageDependency>
  }
}
