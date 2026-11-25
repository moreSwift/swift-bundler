import Testing
import Foundation
import TOMLKit
import Version

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

  static func decodeOverlayGatingTestConfiguration(
    _ contents: String,
    effectiveConfigVersion: Version
  ) throws -> OverlayGatingTestConfiguration {
    try PackageConfiguration.$effectiveConfigVersion.withValue(effectiveConfigVersion) {
      #expect(PackageConfiguration.effectiveConfigVersion == effectiveConfigVersion)
      return try TOMLDecoder().decode(
        OverlayGatingTestConfiguration.self,
        from: contents
      )
    }
  }

  // MARK: - Tests

  @Test func testIntroducedPropertyInOverlayIsRejectedForOlderConfigVersion() throws {
    let contents = """
      value = "base"

      [[overlays]]
      condition = "true"
      new_value = "overlay"
      """

    do {
      _ = try Self.decodeOverlayGatingTestConfiguration(
        contents,
        effectiveConfigVersion: Version(3, 0, 0)
      )
      Issue.record(
        "Expected an @Introduced property set via an overlay to be rejected for a 3.0.0 config"
      )
    } catch let error as PackageConfiguration.Error {
      guard case .propertyNotSupportedByConfigVersion = error.message else {
        Issue.record("Unexpected error: \(error)")
        return
      }
    }
  }

  @Test func testAvailableIntroducedPropertyInOverlayIsRejectedForOlderConfigVersion() throws {
    let contents = """
      [[overlays]]
      condition = "platform(linux)"
      new_linux_value = true
      """

    do {
      _ = try Self.decodeOverlayGatingTestConfiguration(
        contents,
        effectiveConfigVersion: Version(3, 0, 0)
      )
      Issue.record(
        """
        Expected an @Available + @Introduced property set via an overlay to be \
        rejected for a 3.0.0 config
        """
      )
    } catch let error as PackageConfiguration.Error {
      guard case .propertyNotSupportedByConfigVersion = error.message else {
        Issue.record("Unexpected error: \(error)")
        return
      }
    }
  }

  @Test func testIntroducedPropertyInOverlayIsAcceptedForNewConfigVersion() throws {
    let contents = """
      value = "base"

      [[overlays]]
      condition = "true"
      new_value = "overlay"
      """

    let configuration = try Self.decodeOverlayGatingTestConfiguration(
      contents,
      effectiveConfigVersion: Version(3, 1, 0)
    )

    #expect(configuration.value == "base")
    #expect(configuration.newValue == nil)
    #expect(configuration.overlays?.first?.newValue == "overlay")
  }

  @Test func testAvailableIntroducedPropertyInOverlayIsAcceptedForNewConfigVersion() throws {
    let contents = """
      [[overlays]]
      condition = "platform(linux)"
      new_linux_value = true
      """

    let configuration = try Self.decodeOverlayGatingTestConfiguration(
      contents,
      effectiveConfigVersion: Version(3, 1, 0)
    )

    #expect(configuration.newLinuxValue == false)
    #expect(configuration.overlays?.first?.newLinuxValue == true)
  }

  @Test func testPlistAndMetadataOverlayMerging() async throws {
    let contents = """
      format_version = 2

      [apps.HelloWorld]
      product = "HelloWorld"
      identifier = "com.example.HelloWorld"
      version = "1.0.0"

      [apps.HelloWorld.plist]
      BaseOnly = "base"
      Overridden = "base"
      Nested = { BaseOnly = "base", Overridden = "base" }

      [apps.HelloWorld.metadata]
      BaseOnly = "base"
      Overridden = "base"

      [[apps.HelloWorld.overlays]]
      condition = "platform(linux)"
      plist = {
        OverlayOnly = "overlay",
        Overridden = "overlay",
        Nested = { OverlayOnly = "overlay", Overridden = "overlay" }
      }
      metadata = { OverlayOnly = "overlay", Overridden = "overlay" }
      """

    let context = ConfigurationFlattener.Context(
      platform: .linux,
      bundler: .linuxGeneric,
      architectures: [.host]
    )

    let configuration = try await Self.flattenTOMLConfiguration(
      contents,
      with: context
    )

    let app = try #require(configuration.apps["HelloWorld"])

    #expect(app.plist["BaseOnly"] == .string("base"))
    #expect(app.plist["OverlayOnly"] == .string("overlay"))
    #expect(app.plist["Overridden"] == .string("overlay"))
    #expect(
      app.plist["Nested"] == .dictionary([
        "BaseOnly": .string("base"),
        "OverlayOnly": .string("overlay"),
        "Overridden": .string("overlay"),
      ])
    )

    #expect(app.metadata["BaseOnly"] == .string("base"))
    #expect(app.metadata["OverlayOnly"] == .string("overlay"))
    #expect(app.metadata["Overridden"] == .string("overlay"))
  }

  @Test func testV2MigrationDefaultsMissingBundleIdentifier() async throws {
    let contents = """
      [apps.HelloWorld]
      product = "HelloWorld"
      version = "1.0.0"
      """

    let configuration = try await Self.parseTOMLConfiguration(contents)

    #expect(
      configuration.apps?["HelloWorld"]?.identifier == "com.example.HelloWorld"
    )
  }

  @Test func testV2ConfigurationMigrationCreatesBackup() async throws {
    let directory = FileManager.default.temporaryDirectory / UUID().uuidString
    try FileManager.default.createDirectory(at: directory)
    defer {
      try? FileManager.default.removeItem(at: directory)
    }

    let original = """
      [apps.HelloWorld]
      product = "HelloWorld"
      version = "1.0.0"
      bundle_identifier = "com.example.HelloWorld"
      """

    let configurationFile = directory / "Bundler.toml"
    try original.write(to: configurationFile, atomically: true, encoding: .utf8)

    _ = try await PackageConfiguration.load(
      fromDirectory: directory,
      migrateConfiguration: true
    )

    let backupFile = directory / "Bundler.toml.orig"
    let backupExists = FileManager.default.fileExists(atPath: backupFile.path)

    try #require(
      backupExists,
      "Migration should create a backup of the original config"
    )

    let backupContents = try String(contentsOf: backupFile)
    #expect(backupContents == original)
  }

  @Test func testConfigMigrateSucceedsWhenAlreadyUpToDate() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer {
      try? FileManager.default.removeItem(at: directory)
    }

    let contents = """
      format_version = 2

      [apps.HelloWorld]
      product = "HelloWorld"
      identifier = "com.example.HelloWorld"
      version = "1.0.0"
      """

    let configurationFile = directory / "Bundler.toml"
    try contents.write(to: configurationFile, atomically: true, encoding: .utf8)

    let command = try ConfigMigrateCommand.parse([
      "--directory", directory.path,
    ])
    try await command.wrappedRun()

    let contentsAfterMigration = try String(contentsOf: configurationFile)
    #expect(contentsAfterMigration == contents)
  }

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
              version: Version(0, 1, 0),
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
              version: Version(0, 1, 0, pre: ["alpha", "1"]),
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
              version: Version(0, 1, 0, pre: ["alpha", "1"]),
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
            'unsupported format version' error, got '\(message?.userFriendlyMessage ?? "<none>")'
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
            version: Version(0, 1, 0),
            android: AppConfiguration.Android(
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
