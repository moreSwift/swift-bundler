import Foundation
import ErrorKit

extension DarwinBundler {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``DarwinBundler``.
  enum ErrorMessage: Throwable {
    case failedToBuild(product: String)
    case failedToRemoveExistingAppBundle(bundle: URL)
    case failedToCreateAppBundleDirectoryStructure
    case failedToCreatePkgInfo(file: URL)
    case failedToCreateInfoPlist
    case failedToCopyExecutable(source: URL, destination: URL)
    case failedToCopyExecutableDependency(ProjectBuilder.ProductReference)
    case failedToCreateIcon
    case failedToCopyICNS(source: URL, destination: URL)
    case failedToCopyResourceBundles
    case failedToCopyDynamicLibraries
    case failedToRunExecutable
    case invalidAppIconFile(URL)
    case failedToGetMinimumMacOSVersion(manifest: URL)
    case failedToCopyProvisioningProfile
    case missingDarwinPlatformVersion(Platform)
    case unsupportedPlatform(Platform)
    case missingTargetDevice(Platform)
    case failedToGenerateProvisioningProfile
    case missingCodeSigningContextForProvisioning(NonMacAppleOS)

    var userFriendlyMessage: String {
      switch self {
        case .failedToBuild(let product):
          return "Failed to build '\(product)'"
        case .failedToRemoveExistingAppBundle(let bundle):
          return "Failed to remove existing app bundle at '\(bundle.relativePath)'"
        case .failedToCreateAppBundleDirectoryStructure:
          return "Failed to create app bundle directory structure"
        case .failedToCreatePkgInfo(let file):
          return "Failed to create 'PkgInfo' file at '\(file)'"
        case .failedToCreateInfoPlist:
          return "Failed to create 'Info.plist'"
        case .failedToCopyExecutable(let source, let destination):
          return """
            Failed to copy executable from '\(source.relativePath)' to \
            '\(destination.relativePath)'
            """
        case .failedToCopyExecutableDependency(let product):
          return "Failed to copy executable dependency '\(product)'"
        case .failedToCreateIcon:
          return "Failed to create app icon"
        case .failedToCopyICNS(let source, let destination):
          return
            "Failed to copy 'icns' file from '\(source.relativePath)' to '\(destination.relativePath)'"
        case .failedToCopyResourceBundles:
          return "Failed to copy resource bundles"
        case .failedToCopyDynamicLibraries:
          return "Failed to copy dynamic libraries"
        case .failedToRunExecutable:
          return "Failed to run app executable"
        case .invalidAppIconFile(let file):
          return "Invalid app icon file, must be 'png' or 'icns', got '\(file.relativePath)'"
        case .failedToGetMinimumMacOSVersion(let manifest):
          return """
            To build for macOS, please specify a macOS deployment version in the \
            platforms field of '\(manifest.relativePath)'
            """
        case .failedToCopyProvisioningProfile:
          return "Failed to copy provisioning profile to output bundle"
        case .missingDarwinPlatformVersion(let platform):
          return """
            Missing target platform version for \(platform.os.name) in \
            'Package.swift'. Update the `Package.platforms` array and try again.
            """
        case .unsupportedPlatform(let platform):
          return """
            Platform '\(platform.name)' not supported by \
            '\(BundlerChoice.darwinApp.rawValue)' bundler.
            """
        case .missingTargetDevice(let platform):
          return """
            Platform '\(platform.name)' requires a target device t
            """
        case .failedToGenerateProvisioningProfile:
          return "Failed to generate provisioning profile"
        case .missingCodeSigningContextForProvisioning(let os):
          return """
            Missing code signing context (required to generate provisioning \
            profiles for \(os.os.name))
            """
      }
    }
  }
}
