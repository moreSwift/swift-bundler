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
      ListSDKs.self,
    ]
  )

  struct DumpPackageGraph: ErrorHandledCommand {
    static var configuration = CommandConfiguration(
      commandName: "dump-package-graph",
      abstract: "Dumps the package graph of the root package and all of its dependencies"
    )

    /// An alternative Swift toolchain to use.
    @Option(
      help: "An alternative Swift toolchain to use",
      transform: URL.init(fileURLWithPath:))
    var toolchain: URL?

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
            bundler: BundlerChoice.defaultForHostPlatform,
            architectures: [BuildArchitecture.host]
          ),
          toolchain: toolchain
        )
      }

      try displayJSONOutput(graph)
    }
  }

  struct ListSDKs: ErrorHandledCommand {
    static var configuration = CommandConfiguration(
      commandName: "list-sdks",
      abstract: "Lists all SDKs that Swift Bundler knows about"
    )

    @Flag(
      name: .shortAndLong,
      help: "Print verbose error messages.")
    var verbose = false

    @Flag(help: "Display the output as JSON (includes more information)")
    var json = false

    func wrappedRun() async throws(RichError<SwiftBundlerError>) {
      let sdks = try RichError<SwiftBundlerError>.catch {
        try SwiftSDKManager.enumerateInstalledSwiftSDKs()
      }

      try displayOutput(sdks, json: json) { sdk in
        let name = "\(sdk.artifactIdentifier):\(sdk.triple)"
        return KeyedList.Entry(name.bold) {
          sdk.artifactVariant.path
        }
      }
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
