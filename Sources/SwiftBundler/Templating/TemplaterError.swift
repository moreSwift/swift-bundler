import Foundation
import Version
import ErrorKit

extension Templater {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``Templater``.
  enum ErrorMessage: Throwable {
    case packageDirectoryAlreadyExists(URL)
    case cannotCreatePackageFromBaseTemplate
    case failedToCreateOutputDirectory(URL)
    case failedToDecodeTemplateManifest(template: String, manifest: URL)
    case failedToReadTemplateManifest(template: String, manifest: URL)
    case templateDoesNotSupportInstalledSwiftVersion(
      template: Template.Name,
      version: Version,
      minimumSupportedVersion: Version
    )
    case failedToEnumerateTemplateContents(template: Template.Name)
    case failedToReadFile(template: String, file: URL)
    case failedToGetRelativePath(file: URL, base: URL)
    case failedToWriteToOutputFile(file: URL)
    case failedToCreateBareMinimumPackage
    case failedToEnumerateOutputFiles
    case failedToUpdateIndentationStyle(directory: URL)
    case missingVSCodeOverlay
    case templateNotPublic(Template)

    var userFriendlyMessage: String {
      switch self {
        case .packageDirectoryAlreadyExists(let directory):
          return "A directory already exists at '\(directory.relativePath)'"
        case .cannotCreatePackageFromBaseTemplate:
          return "Cannot create a package from the 'Base' template"
        case .failedToCreateOutputDirectory(let directory):
          return "Failed to create package directory at '\(directory.relativePath)'"
        case .failedToDecodeTemplateManifest(let template, _):
          return Output {
            "Failed to decode the manifest for the '\(template)' template"
            ""
            Section("Troubleshooting") {
              "Have you updated your templates recently?"
              ExampleCommand("swift-bundler template update")
            }
          }.description
        case .failedToReadTemplateManifest(let template, _):
          return "Failed to read the contents of the manifest for the '\(template)' template"
        case .templateDoesNotSupportInstalledSwiftVersion(
          let template,
          let version,
          let minimumSupportedVersion
        ):
          return """
            The '\(template)' template supports a minimum Swift version of \
            \(minimumSupportedVersion) but \(version) is installed. Provide \
            the '-f' flag to create the package anyway
            """
        case .failedToEnumerateTemplateContents(let template):
          return "Failed to enumerate the contents of the '\(template)' template"
        case .failedToReadFile(let template, let file):
          return "Failed to read the file '\(file.relativePath)' from the '\(template)' template"
        case .failedToGetRelativePath(let file, let base):
          return "Failed to get relative path from '\(file.relativePath)' to '\(base.relativePath)'"
        case .failedToWriteToOutputFile(let file):
          return "Failed to write to the output file at '\(file.relativePath)'"
        case .failedToCreateBareMinimumPackage:
          return "Failed to create package"
        case .failedToEnumerateOutputFiles:
          return "Failed to enumerate the files in the output directory"
        case .failedToUpdateIndentationStyle(let directory):
          return
            "Failed to update the indentation style of the package in '\(directory.relativePath)'"
        case .missingVSCodeOverlay:
          return Output {
            "Missing VSCode overlay."
            ""
            Section("Troubleshooting") {
              "Your templates may be outdated"
              ExampleCommand("swift-bundler templates update")
            }
          }.description
        case .templateNotPublic(let template):
          return """
            '\(template.name)' is an internal template and cannot be used to \
            create projects directly
            """
      }
    }
  }
}
