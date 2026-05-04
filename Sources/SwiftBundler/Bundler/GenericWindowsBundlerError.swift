import ErrorKit
import Foundation

extension GenericWindowsBundler {
  typealias Error = RichError<ErrorMessage>

  enum ErrorMessage: Throwable {
    case failedToCreateDirectory(URL)
    case failedToCopyExecutableDependency(ProjectBuilder.ProductReference)
    case failedToInsertMetadata
    case failedToCreateAppxManifest(AppxManifestCreator.Error)
    case failedToEnumerateResourceBundles(URL)
    case failedToCopyResourceBundle(source: URL, destination: URL)
    case failedToCopyExecutable(source: URL, destination: URL)
    case failedToParseDumpbinOutput(output: String, message: String)
    case failedToResolveDLLName(String)
    case failedToEnumerateDynamicDependencies
    case failedToCopyDLL(source: URL, destination: URL)
    case failedToCopyPDB(source: URL, destination: URL)
    case failedToLoadIcon(URL)
    case failedToEncodeIco
    case failedToEncodePng
    case failedToDownloadResourceHacker
    case failedToRunResourceHacker
    case failedToLocateResourceHackerExecutable(expectedLocation: URL)

    var userFriendlyMessage: String {
      switch self {
        case .failedToCreateDirectory(let directory):
          return """
            Failed to create directory at \
            '\(directory.path(relativeTo: .currentDirectory))'
            """
        case .failedToCopyExecutableDependency(let product):
          return "Failed to copy dependency '\(product)' to output bundle"
        case .failedToInsertMetadata:
          return "Failed to insert metadata into main executable"
        case .failedToCreateAppxManifest(let appxManifestError):
          return "Failed to create AppX manifest: \(appxManifestError.userFriendlyMessage)"
        case .failedToEnumerateResourceBundles(let directory):
          return """
            Failed to enumerate resource bundles in \
            '\(directory.path(relativeTo: .currentDirectory))'
            """
        case .failedToCopyResourceBundle(let source, let destination):
          return """
            Failed to copy resource bundle from \
            '\(source.path(relativeTo: .currentDirectory))' to \
            '\(destination.path(relativeTo: .currentDirectory))'
            """
        case .failedToCopyExecutable(let source, let destination):
          return """
            Failed to copy executable from \
            '\(source.path(relativeTo: .currentDirectory))' to \
            '\(destination.path(relativeTo: .currentDirectory))'
            """
        case .failedToParseDumpbinOutput(_, let message):
          return "Failed to parse dumpbin output: \(message)"
        case .failedToResolveDLLName(let name):
          return "Failed to resolve path to DLL named '\(name)'"
        case .failedToEnumerateDynamicDependencies:
          return "Failed to run dumpbin"
        case .failedToCopyDLL(let source, let destination):
          return """
            Failed to copy DLL from \
            '\(source.path(relativeTo: .currentDirectory))' to \
            '\(destination.path(relativeTo: .currentDirectory))'
            """
        case .failedToCopyPDB(let source, let destination):
          return """
            Failed to copy PDB from \
            '\(source.path(relativeTo: .currentDirectory))' to \
            '\(destination.path(relativeTo: .currentDirectory))'
            """
        case .failedToLoadIcon(let icon):
          return "Failed to load icon at '\(icon.path(relativeTo: .currentDirectory))'"
        case .failedToEncodeIco:
          return "Failed to encode ico file"
        case .failedToEncodePng:
          return "Failed to encode png file"
        case .failedToDownloadResourceHacker:
          return "Failed to download Resource Hacker"
        case .failedToRunResourceHacker:
          return "Failed to run Resource Hacker"
        case .failedToLocateResourceHackerExecutable(let expectedLocation):
          return """
            Failed to locate Resource Hacker executable in downloaded zip archive. \
            Expected to find it at '\(expectedLocation.path)'
            """
      }
    }
  }
}
