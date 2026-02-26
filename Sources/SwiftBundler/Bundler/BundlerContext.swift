import Foundation

/// The context passed to bundlers.
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

  /// The package graph of the project's root package.
  var packageGraph: SwiftPackageManager.PackageGraph

  /// The architectures that the app has been built for.
  var architectures: [BuildArchitecture]

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
  var builtDependencies: [ProjectBuilder.ProductReference: ProjectBuilder.BuiltProduct]

  /// The app's main built executable file.
  var executableArtifact: URL

  /// The Swift toolchain used to perform the build.
  var swiftToolchain: URL?

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
