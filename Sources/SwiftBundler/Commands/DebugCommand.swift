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
      ListSDKs.self,
      ListToolchains.self,
    ]
  )

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

      try DebugCommand.displayOutput(sdks, json: json) { sdk in
        let name = "\(sdk.artifactIdentifier):\(sdk.triple)"
        return KeyedList.Entry(name.bold) {
          sdk.artifactVariant.path
        }
      }
    }
  }

  struct ListToolchains: ErrorHandledCommand {
    static var configuration = CommandConfiguration(
      commandName: "list-toolchains",
      abstract: "List all Swift Toolchains that Swift Bundler knows about"
    )

    @Flag(
      name: .shortAndLong,
      help: "Print verbose error messages.")
    var verbose = false

    @Flag(help: "Display the output as JSON (includes more information)")
    var json = false

    func wrappedRun() async throws(RichError<SwiftBundlerError>) {
      let toolchains = try await RichError<SwiftBundlerError>.catch {
        try await SwiftToolchainManager.locateSwiftToolchains()
      }

      try DebugCommand.displayOutput(toolchains, json: json) { toolchain in
        KeyedList.Entry(toolchain.displayName.bold, toolchain.root.path)
      }
    }
  }

  static func displayOutput<Item: Encodable>(
    _ items: [Item],
    json: Bool,
    entry: (Item) -> KeyedList.Entry
  ) throws(RichError<SwiftBundlerError>) {
    if json {
      let encoder = JSONEncoder()
      encoder.outputFormatting.insert(.prettyPrinted)
      encoder.outputFormatting.insert(.withoutEscapingSlashes)
      let jsonOutput = try RichError<SwiftBundlerError>.catch {
        try encoder.encode(items)
      }
      guard let string = String(data: jsonOutput, encoding: .utf8) else {
        throw RichError(.failedToEncodeJSONOutput)
      }
      print(string)
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
