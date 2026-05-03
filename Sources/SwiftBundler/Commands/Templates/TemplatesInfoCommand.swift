import ArgumentParser
import Foundation
import Rainbow

/// The subcommand for getting info about a template.
struct TemplatesInfoCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "info",
    abstract: "Get info about a template."
  )

  /// The template to get info about.
  @Argument(
    help: "The template to get info about."
  )
  var template: String

  /// The directory to search for templates in.
  @Option(
    name: .long,
    help: "An alternate directory to search for the template in.",
    transform: URL.init(fileURLWithPath:)
  )
  var templateRepository: URL?

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages."
  )
  public var verbose = false

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    let template = try await RichError<SwiftBundlerError>.catch {
      try await Templater.template(named: self.template, in: templateRepository)
    }

    var exampleCommand =
      "swift bundler create [app-name] --template \(template.name.quotedIfNecessary)"
    if let templateRepository = templateRepository {
      exampleCommand +=
        " --template-repository \(templateRepository.relativePath.quotedIfNecessary)"
    }

    Output {
      Section("Template info") {
        KeyedList {
          KeyedList.Entry("Name", template.name)
          KeyedList.Entry("Description", template.manifest.description)
          KeyedList.Entry(
            "Minimum Swift version",
            template.manifest.minimumSwiftVersion.description
          )
          KeyedList.Entry("Platforms") {
            InlineList(template.manifest.platforms)
          }
        }
      }
      Section("Using this template") {
        ExampleCommand(exampleCommand)
      }
    }.show()
  }
}
