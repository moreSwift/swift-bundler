import ArgumentParser
import Foundation
import Version

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
      ListToolchains.self,
      ListAndroidNDKs.self,
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

      try displayKeyedOutputList(sdks, json: json) { sdk in
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

      try DebugCommand.displayKeyedOutputList(toolchains, json: json) { toolchain in
        KeyedList.Entry(toolchain.displayName.bold, toolchain.root.path)
      }
    }
  }

  struct ListAndroidNDKs: ErrorHandledCommand {
    static var configuration = CommandConfiguration(
      commandName: "list-android-ndks",
      abstract: "List all non-duplicate Android NDKs that Swift Bundler knows about"
    )

    @Flag(
      name: .shortAndLong,
      help: "Print verbose error messages.")
    var verbose = false

    @Flag(help: "Display the output as JSON (includes more information)")
    var json = false

    func wrappedRun() async throws(RichError<SwiftBundlerError>) {
      struct NDKVersion: Encodable {
        var ndk: URL
        var version: Version
      }

      let ndkVersions = try RichError<SwiftBundlerError>.catch {
        let androidSDK = try AndroidSDKManager.locateAndroidSDK()
        return try AndroidSDKManager.enumerateNDKVersions(availableIn: androidSDK)
      }.map { (ndk, version) in
        NDKVersion(ndk: ndk, version: version)
      }

      try DebugCommand.displayKeyedOutputList(ndkVersions, json: json) { ndkVersion in
        KeyedList.Entry(ndkVersion.version.description.bold, ndkVersion.ndk.path)
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

  static func displayKeyedOutputList<Item: Encodable>(
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

  static func displayOutput<Item: Encodable>(
    _ items: [Item],
    json: Bool,
    @OutputBuilder output: () -> String
  ) throws(RichError<SwiftBundlerError>) {
    if json {
      try displayJSONOutput(items)
    } else {
      let output = output()
      print(output)
    }
  }
}
