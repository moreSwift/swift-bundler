import ArgumentParser
import Foundation

/// The subcommand for listing apps in the current Swift Bundler project.
struct ConfigAppsListCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "list",
    abstract: "List apps in the current Swift Bundler project."
  )

  /// The directory containing the package to inspect.
  @Option(
    name: [.customShort("d"), .customLong("directory")],
    help: "The directory containing the package to inspect.",
    transform: URL.init(fileURLWithPath:)
  )
  var packageDirectory: URL?

  @Flag(help: "Format command output as JSON.")
  var json = false

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages."
  )
  var verbose = false

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    let configuration = try await RichError<SwiftBundlerError>.catch {
      try await PackageConfiguration.load(
        fromDirectory: packageDirectory ?? URL(fileURLWithPath: "."),
        migrateConfiguration: false
      )
    }

    let apps = configuration.apps ?? [:]
    let appNames = apps.map(\.key).sorted()
    let appsJSON = appNames.map { appName in
      ["name": appName]
    }

    try DebugCommand.displayOutput(
      appsJSON,
      json: json
    ) {
      if appNames.isEmpty {
        "No apps".italic
      } else {
        List {
          for appName in appNames {
            List.Entry(appName)
          }
        }
      }
    }
  }
}
