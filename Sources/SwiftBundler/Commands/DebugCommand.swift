import ArgumentParser
import ErrorKit
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
      ListWindowsDynamicDependencies.self,
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
      transform: URL.init(fileURLWithPath:)
    )
    var toolchain: URL?

    @Flag(
      name: .shortAndLong,
      help: "Print verbose error messages."
    )
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
      help: "Print verbose error messages."
    )
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
      help: "Print verbose error messages."
    )
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
      help: "Print verbose error messages."
    )
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

  struct ListWindowsDynamicDependencies: ErrorHandledCommand {
    static var configuration = CommandConfiguration(
      commandName: "list-windows-dynamic-dependencies",
      abstract: """
        List all dynamic dependencies of a Windows exe or dll file. Only \
        supported on Windows hosts
        """
    )

    @Argument(
      help: "The exe or dll file to enumerate dependencies of",
      transform: URL.init(fileURLWithPath:)
    )
    var module: URL

    @Flag(name: .shortAndLong, help: "Print verbose error messages.")
    var verbose = false

    @Flag(name: .customLong("include-system-dlls"), help: "Include system DLLs")
    var includeSystemDLLs = false

    @Flag(help: "Display the output as JSON (includes more information)")
    var json = false

    func wrappedRun() async throws(RichError<SwiftBundlerError>) {
      #if !os(Windows)
        log.error("list-windows-dynamic-dependencies is only supported on Windows hosts")
        Foundation.exit(1)
      #else
        let productsDirectory = module.deletingLastPathComponent()

        let dependencies = try await RichError<SwiftBundlerError>.catch {
          var queue = [module]
          var dependencies: [URL] = []

          while !queue.isEmpty {
            let item = queue.removeFirst()
            do {
              let newDependencies = try await GenericWindowsBundler
                .enumerateDynamicLibraryDependencies(
                  module: item,
                  productsDirectory: productsDirectory,
                  systemDLLNameAllowList: includeSystemDLLs
                    ? nil
                    : GenericWindowsBundler.dllBundlingAllowList
                )
            
              for dependency in newDependencies where !dependencies.contains(dependency) {
                queue.append(dependency)
                dependencies.append(dependency)
              }
            } catch {
              log.error("Failed to resolve dependencies of \(item.path)")
              displayError(error, verbose: verbose, displayHints: false)
            }
          }

          return dependencies
        }

        try DebugCommand.displayOutput(dependencies.map(\.path), json: json) {
          List {
            for dependency in dependencies {
              List.Entry(dependency.path)
            }
          }
        }
      #endif
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
