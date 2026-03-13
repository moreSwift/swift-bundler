import Foundation
import ErrorKit

extension ProjectBuilder {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``ProjectBuilder``.
  enum ErrorMessage: Throwable {
    case failedToCloneRepo(URL)
    case failedToWriteBuilderManifest
    case failedToCreateBuilderSourceDirectory(URL)
    case failedToSymlinkBuilderSourceFile
    case failedToBuildBuilder(name: String)
    case builderFailed
    case failedToBuildProject(name: String)
    case failedToCopyProduct(source: URL, destination: URL)
    case failedToBuildRootProjectProduct(name: String)
    case unsupportedRootProjectProductType(
      SwiftPackageManager.ProductType,
      product: String
    )
    case invalidLocalSource(URL)
    case missingProductArtifact(URL, product: String)
    case noSuchBuilder(String, [String])
    case noSuchProject(ProjectReference)
    case noSuchProduct(DependencyReference)
    case noSuchRootProjectProduct(package: SwiftPackageManager.PackageReference, product: String)

    /// An internal error used in control flow.
    case mismatchedGitURL(_ actual: URL, expected: URL)

    var userFriendlyMessage: String {
      switch self {
        case .failedToCloneRepo(let gitURL):
          return "Failed to clone project source repository '\(gitURL)'"
        case .failedToCreateBuilderSourceDirectory:
          return "Failed to create builder source directory"
        case .failedToWriteBuilderManifest:
          return "Failed to write builder manifest"
        case .failedToSymlinkBuilderSourceFile:
          return "Failed to symlink builder source file"
        case .failedToBuildBuilder(let name):
          return "Failed to build builder '\(name)'"
        case .builderFailed:
          return "Failed to run builder"
        case .failedToBuildProject(let name):
          return "Failed to build project '\(name)'"
        case .failedToCopyProduct(let source, _):
          return "Failed to copy product '\(source.lastPathComponent)'"
        case .failedToBuildRootProjectProduct(let name):
          let absoluteName = "\(ProjectConfiguration.rootProjectName).\(name)"
          return "Failed to build product '\(absoluteName)'"
        case .unsupportedRootProjectProductType(_, let product):
          // TODO: Ideally this error message should include the name of the app
          //   that has the dependency.
          return """
            Could not find executable product with name '\(product)' \
            (the ability to depend on library products from SwiftPM \
            packages isn't implemented yet)
            """
        case .invalidLocalSource(let source):
          return """
            Project source directory \
            '\(source.path(relativeTo: .currentDirectory))' doesn't exist
            """
        case .missingProductArtifact(let location, let product):
          return """
            Missing artifact at '\(location.path(relativeTo: .currentDirectory))' \
            required by product '\(product)'
            """
        case .noSuchBuilder(let name, let availableBuilders):
          return """
            No such builder '\(name)'; expected one of \
            \(availableBuilders.joinedGrammatically())
            """
        case .mismatchedGitURL(let actualURL, let expectedURL):
          return """
            Expected repository to have origin url \
            '\(expectedURL.absoluteString)' but had '\(actualURL.absoluteString)'
            """
        case .noSuchProject(let project):
          return """
            No such project '\(project.name)' in package \
            '\(project.package.identity)'
            """
        case .noSuchProduct(let dependency):
          return "Missing product \(dependency)"
        case .noSuchRootProjectProduct(let package, let product):
          return "Product '\(product)' not found in package '\(package)'"
      }
    }
  }
}
