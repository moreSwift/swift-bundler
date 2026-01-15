import Foundation
import Parsing

/// A bundler targeting Android.
enum APKBundler: Bundler {
  static let outputIsRunnable = true
  static let requiresBuildAsDylib = true

  typealias Context = Void

  static func computeContext(
    context: BundlerContext,
    command: BundleCommand,
    manifest: PackageManifest
  ) throws(Error) {}

  static func intendedOutput(
    in context: BundlerContext,
    _ additionalContext: Context
  ) -> BundlerOutputStructure {
    let bundle = context.outputDirectory
      .appendingPathComponent("\(context.appName).apk")
    return BundlerOutputStructure(
      bundle: bundle,
      executable: bundle
    )
  }

  static func bundle(
    _ context: BundlerContext,
    _ additionalContext: Context
  ) async throws(Error) -> BundlerOutputStructure {
    let root = intendedOutput(in: context, additionalContext).bundle
    let appBundleName = root.lastPathComponent

    log.info("Bundling '\(appBundleName)'")

    return BundlerOutputStructure(
      bundle: root,
      executable: root
    )
  }
}
