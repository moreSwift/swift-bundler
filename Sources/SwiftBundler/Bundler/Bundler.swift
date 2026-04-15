import Foundation
import ErrorKit

protocol Bundler {
  associatedtype Context
  associatedtype Error: Throwable

  /// Indicates whether the output of the bundler will be runnable or not. For
  /// example, the output of ``RPMBundler`` is not runnable but the output of
  /// ``AppImageBundler`` is.
  static var outputIsRunnable: Bool { get }

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

extension Bundler where Context == Void {
  static func computeContext(
    context: BundlerContext,
    command: BundleCommand,
    manifest: PackageManifest
  ) throws(Error) {}
}

struct BundlerContext {
  /// The name to give the bundled app.
  var appName: String
  /// The name of the package.
  var packageName: String
  /// The app's configuration.
  var appConfiguration: AppConfiguration.Flat

  /// The root directory of the package containing the app.
  var packageDirectory: URL
  /// The directory containing the products from the build step.
  var productsDirectory: URL
  /// The directory to output the app into.
  var outputDirectory: URL

  /// The target platform.
  var platform: Platform
  /// The target device if any.
  var device: Device?

  /// Code signing information for bundlers that support Darwin code signing.
  ///
  /// Exists in the generic bundler context because Swift Bundler loads codesigning
  /// context up-front to notify users of configuration issues more quickly.
  var darwinCodeSigningContext: DarwinCodeSigningContext?

  /// Code signing information for bundlers that support Windows code signing.
  ///
  /// Exists in the generic bundler context because Swift Bundler loads codesigning
  /// context up-front to notify users of configuration issues more quickly.
  var windowsCodeSigningContext: WindowsCodeSigningContext?

  /// The app's built dependencies.
  var builtDependencies: [String: ProjectBuilder.BuiltProduct]

  /// The app's main built executable file.
  var executableArtifact: URL

  /// Code signing information for bundlers that support Darwin code signing.
  ///
  /// Exists in the generic bundler context because Swift Bundler loads codesigning
  /// context up-front to notify users of configuration issues more quickly.
  struct DarwinCodeSigningContext {
    /// The identity to sign the app with.
    var identity: CodeSigningIdentity
    /// A file containing entitlements to give the app if code signing.
    var entitlements: URL?
    /// A provisioning profile provided by the user.
    var manualProvisioningProfile: URL?
  }

  /// Code signing information for bundlers that support Windows code signing.
  ///
  /// Exists in the generic bundler context because Swift Bundler loads codesigning
  /// context up-front to notify users of configuration issues more quickly.
  enum WindowsCodeSigningContext {
    /// Sign files using Azure Artifact Signing.
    case azureArtifactSigning(metadata: URL)
    /// Sign files using a local code signing certificate stored in the user's
    /// certificate store.
    case localCertificate(identity: CodeSigningIdentity)
  }
}

/// Describes the basic structure of a bundler's output. Shouldn't describe
/// intermediate files, only the useful final outputs of the bundler.
struct BundlerOutputStructure {
  /// The bundle itself.
  var bundle: URL
  /// The actual executable file to run when the user instructs Swift Bundler
  /// to run the app. If `nil`, it's assumed that the bundler doesn't support
  /// running.
  var executable: URL?
  /// Any other files produced that might be useful wnen distributing the app,
  /// e.g. a `.desktop` file on Linux.
  var additionalOutputs: [URL] = []
}

/// A variation on ``BundlerOutputStructure`` validated as runnable, guarantees
/// that the output contains an executable (or at least claims it does).
struct RunnableBundlerOutputStructure {
  /// The bundle itself.
  var bundle: URL
  /// The actual executable file to run when the user instructs Swift Bundler
  /// to run the app.
  var executable: URL

  /// Validates a bundler's output for 'runnability' (i.e. it claims to have
  /// produced an executable).
  init?(_ output: BundlerOutputStructure) {
    guard let executable = output.executable else {
      return nil
    }
    bundle = output.bundle
    self.executable = executable
  }
}
