import ArgumentParser
import Foundation

/// The subcommand containing debug commands to use when debugging Swift
/// Bundler issues or working on Swift Bundler features.
struct DebugCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "_debug",
    abstract: "A home for debugging commands",
    shouldDisplay: false,
    subcommands: [
      DumpPackageGraph.self,
    ]
  )

  struct DumpPackageGraph: ErrorHandledCommand {
    static var configuration = CommandConfiguration(
      commandName: "dump-package-graph",
      abstract: "Dumps the package graph of the root package and all of its dependencies"
    )

    @Flag(
      name: .shortAndLong,
      help: "Print verbose error messages.")
    var verbose = false

    func wrappedRun() async throws(RichError<SwiftBundlerError>) {
      let graph = try await RichError<SwiftBundlerError>.catch {
        try await SwiftPackageManager.loadPackageGraph(
          packageDirectory: .currentDirectory,
          configurationContext: ConfigurationFlattener.Context(
            platform: HostPlatform.hostPlatform.platform,
            bundler: BundlerChoice.defaultForHostPlatform
          ),
          toolchain: nil
        )
      }

      try displayJSONOutput(graph)
    }
  }

  static func displayJSONOutput<Item: Encodable>(
    _ item: Item
  ) throws(RichError<SwiftBundlerError>) {
    let encoder = JSONEncoder()
    encoder.outputFormatting.insert(.prettyPrinted)
    encoder.outputFormatting.insert(.withoutEscapingSlashes)
    let jsonOutput = try RichError<SwiftBundlerError>.catch {
      try encoder.encode(item)
    }
    guard let string = String(data: jsonOutput, encoding: .utf8) else {
      throw RichError(.failedToEncodeJSONOutput)
    }
    print(string)
  }

  static func displayOutput<Item: Encodable>(
    _ items: [Item],
    json: Bool,
    entry: (Item) -> KeyedList.Entry
  ) throws(RichError<SwiftBundlerError>) {
    if json {
      try displayJSONOutput(items)
    } else {
      let output = KeyedList {
        for item in items {
          entry(item)
        }
      }

      print(output.description)
    }
  }
}
