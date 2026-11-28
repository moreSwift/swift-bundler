import Foundation
import ErrorKit

extension DynamicLibraryBundler {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``DynamicLibraryBundler``.
  enum ErrorMessage: Throwable {
    case failedToEnumerateDynamicLibraries(directory: URL)
    case failedToUpdateLibraryInstallName(binary: URL, original: String, new: String)
    case failedToUpdateAppRPaths(binary: URL)
    case failedToEnumerateRPaths(binary: URL)
    case failedToEnumerateDynamicDependencies(binary: URL)
    case failedToSignMovedLibrary
    case failedToLocateDynamicDependency(installName: String)
    case failedToMakeLibraryWritable(library: URL)

    var userFriendlyMessage: String {
      switch self {
        case .failedToEnumerateDynamicLibraries(let directory):
          return "Failed to enumerate dynamic libraries in '\(directory.relativePath)'"
        case .failedToUpdateLibraryInstallName(let binary, let original, let new):
          let binaryPath = binary.path(relativeTo: .currentDirectory)
          return """
            Failed to update dynamic library install name from \
            '\(original)' to '\(new)' in '\(binaryPath)'
            """
        case .failedToUpdateAppRPaths(let binary):
          let binaryPath = binary.path(relativeTo: .currentDirectory)
          return "Failed to update the rpaths of '\(binaryPath)'"
        case .failedToEnumerateRPaths(let binary):
          let binaryPath = binary.path(relativeTo: .currentDirectory)
          return "Failed to enumerate the rpaths of '\(binaryPath)'"
        case .failedToEnumerateDynamicDependencies(let binary):
          let binaryPath = binary.path(relativeTo: .currentDirectory)
          return """
            Failed to enumerate dynamic dependencies of '\(binaryPath)'
            """
        case .failedToSignMovedLibrary:
          return "Failed to sign relocated dynamic library using the ad-hoc signing method"
        case .failedToLocateDynamicDependency(let installName):
          return "Failed to locate dynamic dependency with install name '\(installName)'"
        case .failedToMakeLibraryWritable(let library):
          let libraryPath = library.path(relativeTo: .currentDirectory)
          return "Failed to make '\(libraryPath)' writable"
      }
    }
  }
}
