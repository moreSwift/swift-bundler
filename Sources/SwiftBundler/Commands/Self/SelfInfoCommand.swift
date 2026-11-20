import ArgumentParser
import Foundation
import SwiftBundlerRuntime

/// Prints information about the current Swift Bundler installation as JSON.
struct SelfInfoCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "info",
    abstract: "Print information about this Swift Bundler installation as JSON."
  )

  @Flag(
    help: "Produce machine-readable JSON output. Also includes more information."
  )
  var json = false

  func run() async throws {
    let metadata = try Metadata.loadEmbedded()
    let installationMethod =
      metadata?.additionalMetadata["installationMethod"] as? String ?? "custom"

    let executable = Bundle.main.executableURL?
      .actuallyResolvingSymlinksInPath().path
    let identifier = metadata?.appIdentifier ?? "dev.moreswift.swift-bundler"
    let version = metadata?.appVersion ?? SwiftBundler.version.description

    if json {
      var info: [String: Any] = [
        "installationMethod": installationMethod,
        "version": version,
        "executable": executable as Any,
      ]

      if let metadata {
        info["metadata"] = [
          "appIdentifier": identifier,
          "appVersion": version,
          "additionalMetadata": metadata.additionalMetadata,
        ] as [String: Any]
      }

      let data = try JSONSerialization.data(
        withJSONObject: info,
        options: [.sortedKeys, .withoutEscapingSlashes]
      )

      guard let json = String(data: data, encoding: .utf8) else {
        throw ValidationError("Failed to encode installation information as UTF-8")
      }
      print(json)
    } else {
      let output = KeyedList {
        KeyedList.Entry("Version", version)
        KeyedList.Entry("Identifier", identifier)
        KeyedList.Entry("Executable", executable ?? "<unknown>")
        KeyedList.Entry("Installation method", installationMethod)
      }
      print(output.description)
    }
  }
}
