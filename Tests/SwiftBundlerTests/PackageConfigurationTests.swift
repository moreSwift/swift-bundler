import Testing
import Foundation

@testable import SwiftBundler

@Suite(.serialized)
struct PackageConfigurationTests {
  // MARK: - Helpers

  static func parseTOMLConfiguration(
    _ contents: String,
    location: URL? = nil,
    packageDirectory: URL? = nil
  ) async throws(PackageConfiguration.Error) -> PackageConfiguration {
    let location = location ?? URL(fileURLWithPath: "/Bundler.toml")
    let packageDirectory = packageDirectory ?? location.deletingLastPathComponent()
    return try await PackageConfiguration.loadTOMLConfiguration(
      location,
      contents: contents,
      fromDirectory: packageDirectory,
      migrateConfiguration: false
    )
  }

  static func flattenTOMLConfiguration(
    _ contents: String,
    location: URL? = nil,
    packageDirectory: URL? = nil,
    with context: ConfigurationFlattener.Context
  ) async throws -> PackageConfiguration.Flat {
    let configuration = try await parseTOMLConfiguration(
      contents,
      location: location,
      packageDirectory: packageDirectory
    )

    return try ConfigurationFlattener.flatten(
      configuration,
      with: context
    )
  }

  // MARK: - Tests

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

    do {
      _ = try await Self.parseTOMLConfiguration(contents)

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

  @Test func testDictionaryLikePropertyMerging() async throws {
    let contents = """
      format_version = 2

      [apps.HelloWorld]
      product = "HelloWorld"
      identifier = "com.example.HelloWorld"
      version = "0.1.0"
      android.version_code = 1

      [[apps.HelloWorld.overlays]]
      condition = "arch(arm64)"
      android.compile_sdk = 37
      """

    let context = ConfigurationFlattener.Context(
      platform: .macOS,
      bundler: .windowsMSI,
      architectures: [.arm64]
    )

    let flatConfiguration = try await Self.flattenTOMLConfiguration(
      contents,
      with: context
    )

    let expected = try ConfigurationFlattener.flatten(
      PackageConfiguration(
        apps: [
          "HelloWorld": AppConfiguration(
            identifier: "com.example.HelloWorld",
            product: "HelloWorld",
            version: "0.1.0",
            android: AndroidConfiguration(
              minSDK: nil,
              targetSDK: nil,
              compileSDK: 37,
              versionCode: 1,
              permissions: nil
            )
          )
        ]
      ),
      with: context
    )

    #expect(flatConfiguration == expected)
  }

  @Test func testWindowsManifestMerging() async throws {
    let contents = """
      format_version = 2

      [apps.HelloWorld]
      product = "HelloWorld"
      identifier = "com.example.HelloWorld"
      version = "0.1.0"
      windows.manifest.assemblyIdentity.name = "Hello World"
      windows.manifest.trustInfo.security.requestedPrivileges = [
        {
          requestedExecutionLevel = { level = "requireAdministrator", uiAccess = false }
        }
      ]

      [[apps.HelloWorld.overlays]]
      condition = "arch(arm64)"
      windows.manifest.assemblyIdentity.processorArchitecture = "arm64"
      """

    let context = ConfigurationFlattener.Context(
      platform: .macOS,
      bundler: .windowsMSI,
      architectures: [.arm64]
    )

    let flattenedConfiguration = try await Self.flattenTOMLConfiguration(
      contents,
      with: context
    )

    let flatContents = """
      format_version = 2

      [apps.HelloWorld]
      product = "HelloWorld"
      identifier = "com.example.HelloWorld"
      version = "0.1.0"
      windows.manifest.assemblyIdentity = {
        name = "Hello World",
        processorArchitecture = "arm64"
      }
      windows.manifest.trustInfo.security.requestedPrivileges = [
        {
          requestedExecutionLevel = { level = "requireAdministrator", uiAccess = false }
        }
      ]
      """

    let expected = try await Self.flattenTOMLConfiguration(
      flatContents,
      with: context
    )

    #expect(flattenedConfiguration == expected)
  }
}
