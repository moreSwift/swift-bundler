import Testing
import Foundation

@testable import SwiftBundler

@Suite(.serialized)
struct PackageConfigurationTests {
  /// Ensure that we can correctly load a Swift Bundler 1.x configuration file.
  @Test func testSwiftBundlerV1ConfigurationLoading() async throws {
    try await withFixture("Configuration/V1") { fixture in
      let configuration = try await PackageConfiguration.load(fromDirectory: fixture)
      #expect(
        configuration == PackageConfiguration(
          apps: [
            "HelloWorld": AppConfiguration(
              identifier: "com.example.HelloWorld",
              product: "HelloWorld",
              version: "0.1.0",
              category: "public.app-category.games",
              plist: [
                "Key": .string("Value")
              ]
            )
          ]
        )
      )
    }
  }

  @Test func testSwiftBundlerV2ConfigurationLoading() async throws {
    try await withFixture("Configuration/V2") { fixture in
      let configuration = try await PackageConfiguration.load(fromDirectory: fixture)
      #expect(
        configuration == PackageConfiguration(
          apps: [
            "DeltaClient": AppConfiguration(
              identifier: "dev.stackotter.delta-client",
              product: "DeltaClient",
              version: "0.1.0-alpha.1",
              category: "public.app-category.games",
              icon: "AppIcon.icns",
              plist: [
                "CFBundleShortVersionString": .string("0.1.0-alpha.1-release"),
                "GCSupportsControllerUserInteraction": .string("True")
              ]
            )
          ]
        )
      )
    }
  }

  @Test func testSwiftBundlerV3ConfigurationLoading() async throws {
    try await withFixture("Configuration/V3") { fixture in
      let configuration = try await PackageConfiguration.load(fromDirectory: fixture)
      #expect(
        configuration == PackageConfiguration(
          apps: [
            "DeltaClient": AppConfiguration(
              identifier: "dev.stackotter.delta-client",
              product: "DeltaClient",
              version: "0.1.0-alpha.1",
              category: "public.app-category.games",
              icon: "AppIcon.icns",
              plist: [
                "CFBundleShortVersionString": .string("0.1.0-alpha.1-release"),
                "GCSupportsControllerUserInteraction": .string("True"),
                "MetalCaptureEnabled": .boolean(true)
              ]
            )
          ]
        )
      )
    }
  }

  @Test func testSwiftBundlerV3ConfigurationLoadingWithInvalidFormatVersion() async throws {
    let contents = """
      format_version = 4

      [apps.HelloWorld]
      product = "HelloWorld"
      identifier = "com.example.HelloWorld"
      version = "0.1.0"
      """

    let location = URL(fileURLWithPath: "/Bundler.toml")
    let packageDirectory = location.deletingLastPathComponent()

    do {
      _ = try await PackageConfiguration.loadTOMLConfiguration(
        location,
        contents: contents,
        fromDirectory: packageDirectory,
        migrateConfiguration: false
      )
      Issue.record("Parsing a config file with a format_version > 3 must fail")
    } catch let error {
      switch error.message {
        case .unsupportedFormatVersion(4):
          break
        case let message:
          Issue.record(
            """
            Parsing a config file with a format_version > 3 must fail with an \
            'unsupported format version' error, got '\(message)'
            """
          )
      }
    }
  }
}
