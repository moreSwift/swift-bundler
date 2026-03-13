import Foundation
import ErrorKit

extension GenericLinuxBundler {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``GenericLinuxBundler``.
  enum ErrorMessage: Throwable {
    case failedToCreateBundleStructure(root: URL)
    case failedToCopyExecutable(source: URL, destination: URL)
    case failedToCopyExecutableDependency(
      ProjectBuilder.ProductReference,
      source: URL,
      destination: URL
    )
    case failedToCopyIcon(source: URL, destination: URL)
    case failedToCreateDesktopFile(URL)
    case failedToCreateDBusServiceFile(URL)
    case failedToCreateSymlink(source: URL, relativeDestination: String)
    case failedToCopyResourceBundle(source: URL, destination: URL)
    case failedToEnumerateResourceBundles(directory: URL)
    case failedToEnumerateDynamicDependencies
    case failedToCopyDynamicLibrary(source: URL, destination: URL)
    case failedToUpdateMainExecutableRunpath(executable: URL)

    var userFriendlyMessage: String {
      switch self {
        case .failedToCreateBundleStructure(let root):
          return "Failed to create app bundle directory structure at '\(root)'"
        case .failedToCopyExecutable(let source, let destination):
          return """
            Failed to copy executable from '\(source.relativePath)' to \
            '\(destination.relativePath)'
            """
        case .failedToCopyExecutableDependency(let product, let source, let destination):
          return
            """
            Failed to copy executable dependency '\(product)' from \
            '\(source.relativePath)' to '\(destination.relativePath)'
            """
        case .failedToCopyIcon(let source, let destination):
          return """
            Failed to copy 'icns' file from '\(source.relativePath)' to \
            '\(destination.relativePath)'
            """
        case .failedToCreateDesktopFile(let file):
          return "Failed to create desktop file at '\(file.relativePath)'"
        case .failedToCreateDBusServiceFile(let file):
          return "Failed to create DBus service file at '\(file.relativePath)'"
        case .failedToCreateSymlink(let source, let destination):
          return """
            Failed to create symlink from '\(source.relativePath)' to relative \
            path '\(destination)'
            """
        case .failedToCopyResourceBundle(let source, let destination):
          return """
            Failed to copy resource bundle at '\(source.relativePath)' to \
            '\(destination.relativePath)'
            """
        case .failedToEnumerateResourceBundles(let directory):
          return "Failed to enumerate resource bundles in '\(directory.relativePath)'"
        case .failedToEnumerateDynamicDependencies:
          return "Failed to enumerate dynamically linked dependencies of main executable"
        case .failedToCopyDynamicLibrary(let source, let destination):
          return """
            Failed to copy dynamic library from '\(source.relativePath)' to \
            '\(destination.relativePath)'
            """
        case .failedToUpdateMainExecutableRunpath(let executable):
          return """
            Failed to update the runpath of the main executable at \
            '\(executable.relativePath)'
            """
      }
    }
  }
}
