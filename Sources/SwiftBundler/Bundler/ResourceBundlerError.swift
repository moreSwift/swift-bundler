import ErrorKit
import Foundation

extension ResourceBundler {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``ResourceBundler``.
  enum ErrorMessage: Throwable {
    case failedToEnumerateBundles(directory: URL)
    case failedToCopyBundle(source: URL, destination: URL)
    case failedToCreateBundleDirectory(URL)
    case failedToCreateInfoPlist(file: URL)
    case failedToCopyResource(source: URL, destination: URL)
    case failedToEnumerateBundleContents(directory: URL)
    case failedToCompileMetalShaders
    case failedToCompileXCAssets
    case failedToDeleteAssetCatalog(URL)
    case failedToCompileStringsCatalogs
    case failedToCompileStoryboards

    var userFriendlyMessage: String {
      switch self {
        case .failedToEnumerateBundles(let directory):
          let directoryPath = directory.path(relativeTo: .currentDirectory)
          return "Failed to enumerate bundles in directory at '\(directoryPath)'"
        case .failedToCopyBundle(let source, let destination):
          let sourcePath = source.path(relativeTo: .currentDirectory)
          let destinationPath = destination.path(relativeTo: .currentDirectory)
          return "Failed to copy bundle from '\(sourcePath)' to '\(destinationPath)'"
        case .failedToCreateBundleDirectory(let directory):
          let directoryPath = directory.path(relativeTo: .currentDirectory)
          return "Failed to create bundle directory at '\(directoryPath)'"
        case .failedToCreateInfoPlist(let file):
          let filePath = file.path(relativeTo: .currentDirectory)
          return "Failed to create bundle 'Info.plist' at \(filePath)"
        case .failedToCopyResource(let source, let destination):
          let sourcePath = source.path(relativeTo: .currentDirectory)
          let destinationPath = destination.path(relativeTo: .currentDirectory)
          return "Failed to copy resource from '\(sourcePath)' to '\(destinationPath)'"
        case .failedToEnumerateBundleContents(let directory):
          let directoryPath = directory.path(relativeTo: .currentDirectory)
          return "Failed to enumerate bundle contents at '\(directoryPath)'"
        case .failedToCompileMetalShaders:
          return "Failed to compile Metal shaders"
        case .failedToCompileXCAssets:
          return "Failed to compile XCAssets with 'actool'"
        case .failedToDeleteAssetCatalog(let catalog):
          let catalogPath = catalog.path(relativeTo: .currentDirectory)
          return "Failed to delete asset catalog at '\(catalogPath)' after compilation"
        case .failedToCompileStringsCatalogs:
          return "Failed to compile strings catalogs"
        case .failedToCompileStoryboards:
          return "Failed to compile storyboards"
      }
    }
  }
}
