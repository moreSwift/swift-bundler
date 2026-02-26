import Foundation
import ErrorKit

/// A bundler that bundles built artefacts into distributable apps.
protocol Bundler {
  associatedtype Context
  associatedtype Error: Throwable

  /// Indicates whether the output of the bundler will be runnable or not. For
  /// example, the output of ``RPMBundler`` is not runnable but the output of
  /// ``AppImageBundler`` is.
  static var outputIsRunnable: Bool { get }

  /// Indicates whether the bundler requires the app to be built as a dylib.
  /// If true, Swift Bundler will build the app as a dylib instead of an
  /// executable before passing it to the bundler.
  static var requiresBuildAsDylib: Bool { get }

  /// Checks whether the bundler is compatible with the current host. This
  /// may include checking the host's architecture, it's OS, or the presence
  /// installed dependencies, among other things. An error is thrown to indicate
  /// incompatibility.
  static func checkHostCompatibility() throws(Error)

  /// Computes the bundler's own context given the generic bundler context
  /// and Swift bundler's parsed command-line arguments, options, and flags.
  ///
  /// This step is split out from ``bundle(_:_:)`` and ``intendedOutput(in:_:)``
  /// to maximise the reusability of bundlers. If every bundler required the
  /// full set of command-line arguments to do anything at all then they'd all
  /// be pretty cumbersome to use in non-command-line contexts. Additionally,
  /// this design allows for bundlers to expose niche configuration options
  /// for non-command-line users to use while still keeping command-line code
  /// generic (i.e. no bundlers should require special treatment).
  static func computeContext(
    context: BundlerContext,
    command: BundleCommand,
    manifest: PackageManifest
  ) throws(Error) -> Context

  /// Prepares additional build inputs/arguments to pass to the Swift Package
  /// Manager build command when building the application's main executable.
  /// - Parameters:
  ///   - context: The general context passed to all bundlers.
  ///   - additionalContext: The bundler-specific context for this bundler.
  ///   - dryRun: If true, the bundler should avoid as much destructive/expensive
  ///     work as possible.
  /// - Returns: Additional arguments to pass to Swift Package Manager.
  static func prepareAdditionalSPMBuildArguments(
    _ context: BundlerContext,
    _ additionalContext: Context,
    dryRun: Bool
  ) async throws(Error) -> [String]

  /// Bundles an app from a package's built products directory.
  /// - Parameters:
  ///   - context: The general context passed to all bundlers.
  ///   - additionalContext: The bundler-specific context for this bundler.
  /// - Returns: The URL of the produced app bundle on success.
  static func bundle(
    _ context: BundlerContext,
    _ additionalContext: Context
  ) async throws(Error) -> BundlerOutputStructure

  /// Returns a description of the files that would be produced if
  /// ``Bundler/bundle(_:_:)`` were to get called with the provided context.
  static func intendedOutput(
    in context: BundlerContext,
    _ additionalContext: Context
  ) -> BundlerOutputStructure
}

extension Bundler {
  static func prepareAdditionalSPMBuildArguments(
    _ context: BundlerContext,
    _ additionalContext: Context,
    dryRun: Bool
  ) async throws(Error) -> [String] {
    []
  }
}

extension Bundler {
  static func checkHostCompatibility() throws(Error) {}
}

extension Bundler where Context == Void {
  static func computeContext(
    context: BundlerContext,
    command: BundleCommand,
    manifest: PackageManifest
  ) throws(Error) {}
}
