import Foundation
import ErrorKit

extension APKBundler {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``APKBundler``.
  enum ErrorMessage: Throwable {
    case failedToCreateProjectStructure(root: URL)
    case failedToCreateGradleWrapperFiles
    case failedToCreateGradleConfigurationFiles
    case failedToCreateGradleProjectSourceFiles
    case failedToCreateGradleProjectResourceFiles
    case failedToCopyIcon(source: URL, destination: URL)
    case failedToCreateDefaultIcon(_ destination: URL)
    case multiArchitectureBuildsNotSupported
    case failedToCopyExecutable(source: URL, destination: URL)
    case hostRequiresX86_64Compatibility
    case failedToEnumerateDynamicDependenciesOfLibrary(_ library: URL)
    case failedToLocateDynamicDependencyOfLibrary(
      _ library: URL,
      dependencyName: String,
      guesses: [URL]
    )
    case failedToCopyDynamicDependency(URL)
    case failedToCopyAPK(_ source: URL, _ destination: URL)

    var userFriendlyMessage: String {
      switch self {
        case .failedToCreateProjectStructure(let root):
          let path = root.path(relativeTo: .currentDirectory)
          return "Failed to create Gradle project structure at '\(path)'"
        case .failedToCreateGradleWrapperFiles:
          return "Failed to create gradle wrapper files"
        case .failedToCreateGradleConfigurationFiles:
          return "Failed to create Gradle configuration files"
        case .failedToCreateGradleProjectSourceFiles:
          return "Failed to create Gradle project source files"
        case .failedToCreateGradleProjectResourceFiles:
          return "Failed to create Gradle project resource files"
        case .failedToCopyIcon(let source, let destination):
          let source = source.path(relativeTo: .currentDirectory)
          let destination = destination.path(relativeTo: .currentDirectory)
          return "Failed to copy icon from '\(source)' to '\(destination)'"
        case .failedToCreateDefaultIcon(let destination):
          let destination = destination.path(relativeTo: .currentDirectory)
          return "Failed to create default Android app icon at \(destination)"
        case .multiArchitectureBuildsNotSupported:
          return "Multi-architecture builds not supported"
        case .failedToCopyExecutable(let source, let destination):
          let source = source.path(relativeTo: .currentDirectory)
          let destination = destination.path(relativeTo: .currentDirectory)
          return "Failed to copy executable from '\(source)' to '\(destination)'"
        case .hostRequiresX86_64Compatibility:
          // Ref: https://github.com/android/ndk/issues/1752
          return """
            APKBundler requires an x86_64-compatible host due to Android NDK \
            limitations. Apple Silicon Macs count as x86_64-compatible because \
            of Rosetta
            """
        case .failedToEnumerateDynamicDependenciesOfLibrary(let library):
          return """
            Failed to enumerate dynamic dependencies of library at '\(library.path)'
            """
        case .failedToLocateDynamicDependencyOfLibrary(
          let library, let dependencyName, let guesses
        ):
          let joinedGuesses = guesses.map(\.path).joinedGrammatically()
          return """
            Failed to locate dependency '\(dependencyName)' of library '\(library.path)'; \
            tried \(joinedGuesses)
            """
        case .failedToCopyDynamicDependency(let location):
          return "Failed to copy dynamic dependency '\(location.path)' into bundle"
        case .failedToCopyAPK(let source, let destination):
          let source = source.path(relativeTo: .currentDirectory)
          let destination = destination.path(relativeTo: .currentDirectory)
          return "Failed to copy APK from '\(source)' to '\(destination)'"
      }
    }
  }
}
