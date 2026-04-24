import Foundation

struct BundleCommandContext {
  var packageDirectory: URL
  var manifest: PackageManifest
  var configuration: PackageConfiguration.Flat
  var appName: String
  var appConfiguration: AppConfiguration.Flat
  var configurationFlattenerContext: ConfigurationFlattener.Context

  var platform: Platform
  var platformVersion: String?
  var architectures: [BuildArchitecture]
  var device: Device?

  var bundler: BundlerChoice
  var toolchain: URL?
  var swiftSDK: SwiftSDK?
}
