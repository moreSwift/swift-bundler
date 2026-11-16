import ArgumentParser
import Foundation
import SwiftBundlerRuntime

/// Commands for inspecting the Swift Bundler installation itself.
struct SelfCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "self",
    abstract: "Inspect the Swift Bundler installation.",
    subcommands: [InfoCommand.self]
  )
}

extension SelfCommand {
  /// Prints information about the current Swift Bundler installation as JSON.
  struct InfoCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
      commandName: "info",
      abstract: "Print information about this Swift Bundler installation as JSON."
    )

    func run() async throws {
      let metadata = try Metadata.loadEmbedded()
      let installationMethod =
        metadata?.additionalMetadata["installationMethod"] as? String ?? "custom"

      var info: [String: Any] = [
        "installationMethod": installationMethod,
        "version": SwiftBundler.version.description,
        "executable": URL(fileURLWithPath: Swift.CommandLine.arguments[0])
          .resolvingSymlinksInPath().path,
      ]

      if let metadata {
        info["metadata"] = [
          "appIdentifier": metadata.appIdentifier,
          "appVersion": metadata.appVersion,
          "additionalMetadata": metadata.additionalMetadata,
        ] as [String: Any]
      }

      let data = try JSONSerialization.data(
        withJSONObject: info,
        options: [.prettyPrinted, .sortedKeys]
      )
      guard let json = String(data: data, encoding: .utf8) else {
        throw ValidationError("Failed to encode installation information as UTF-8")
      }
      print(json)
    }
  }
}
