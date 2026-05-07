import Testing
import TOMLKit
import XMLCoder
import Foundation

@testable import SwiftBundler

@Suite(.serialized)
struct Tests {
  @Test func testCommandLineParsing() throws {
    let commandLine = CommandLine.lenientParse(
      "./path/to/my\\ command arg1 'arg2 with spaces' \"arg3 with spaces\" arg4\\ with\\ spaces"
    )

    #expect(
      commandLine
      ==
      CommandLine(
        command: "./path/to/my command",
        arguments: [
          "arg1",
          "arg2 with spaces",
          "arg3 with spaces",
          "arg4 with spaces",
        ]
      )
    )
  }

  @Test func testConditionParsingRoundTripping() async throws {
    let conditions =
      Platform.allCases.map(\.rawValue).map(OverlayCondition.platform)
        + BundlerChoice.allCases.map(\.rawValue).map(OverlayCondition.bundler)

    for condition in conditions {
      let encoded = try JSONEncoder().encode(condition)
      let decoded = try JSONDecoder().decode(OverlayCondition.self, from: encoded)
      #expect(condition == decoded)
    }
  }

  @Test func testSwiftCompilerVersionParsing() throws {
    let testCases: [(
      versionString: String,
      expected: (variant: String?, shortVersion: String, exactVersion: String)
    )] = [
      (
        "Apple Swift version 6.1.2 (swiftlang-6.1.2.1.2 clang-1700.0.13.5)",
        ("Apple", "6.1.2", "6.1.2.1.2")
      ),
      (
        "SwiftWasm Swift version 5.9.2 (swift-5.9.2-RELEASE)",
        ("SwiftWasm", "5.9.2", "5.9.2-RELEASE")
      ),
      (
        "Apple Swift version 6.0.3 (swiftlang-6.0.3.1.10 clang-1600.0.30.1)",
        ("Apple", "6.0.3", "6.0.3.1.10")
      ),
      (
        "Apple Swift version 6.3-dev (LLVM 732b15bc343f6d4, Swift aec3d15e6fbe41c)",
        ("Apple", "6.3-dev", "aec3d15e6fbe41c")
      ),
      (
        "Swift version 6.3-dev effective-5.10 (Swift aec3d15e6fbe41c)",
        (nil, "6.3-dev", "aec3d15e6fbe41c")
      ),
      (
        "swift-driver version: 1.120.5 Apple Swift version 6.1.2 (swiftlang-6.1.2.1.2 clang-1700.0.13.5)",
        ("Apple", "6.1.2", "6.1.2.1.2")
      )
    ]

    for testCase in testCases {
      let version = try SwiftToolchainManager.parseSwiftCompilerVersionString(
        testCase.versionString
      )
      #expect(version.variant == testCase.expected.variant)
      #expect(version.shortVersion == testCase.expected.shortVersion)
      #expect(version.exactVersion == testCase.expected.exactVersion)
    }
  }

  /// Generates a Windows application manifest for use in other tests. Exercises
  /// WindowsManifestTool's manifest merging capability.
  private func generateWindowsManifest() -> WindowsApplicationManifest {
    WindowsManifestTool.generateApplicationManifest(
      for: URL(fileURLWithPath: "helper-tool.exe"),
      name: "helper-tool",
      version: "1.0.0",
      architecture: .arm64,
      overlay: WindowsApplicationManifest(
        assemblyIdentity: WindowsApplicationManifest.AssemblyIdentity(version: "1.0.0.1"),
        trustInfo: WindowsApplicationManifest.TrustInfo(
          xmlns: nil,
          security: WindowsApplicationManifest.TrustInfo.Security(
            requestedPrivileges: [
              .requestedExecutionLevel(level: Attribute(.some("requireAdministrator")), uiAccess: Attribute(.some(false)))
            ]
          )
        )
      )
    )
  }

  @Test(
    """
    Ensures that we correctly merge Windows application manifests, and that we \
    encode them correctly
    """
  )
  func testWindowsManifestGeneration() throws {
    let manifest = generateWindowsManifest()
    let data = try manifest.encode()
    let string = try #require(String(data: data, encoding: .utf8))

    let expected = """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
          <assemblyIdentity version="1.0.0.1" processorArchitecture="arm64" name="helper-tool" type="win32" />
          <trustInfo xmlns="urn:schemas-microsoft-com:asm.v2">
              <security>
                  <requestedPrivileges>
                      <requestedExecutionLevel level="requireAdministrator" uiAccess="false" />
                  </requestedPrivileges>
              </security>
          </trustInfo>
          <file name="helper-tool.exe" />
      </assembly>
      """

    #expect(string == expected)
  }

  @Test(
    """
    Ensures that we correctly decode TOML-formatted partial Windows application manifests
    """
  )
  func testWindowsManifestTOMLDecoding() throws {
    let partialManifest = """
      manifestVersion = '1.0'

      [assemblyIdentity]
      name = 'helper-tool'
      processorArchitecture = 'arm64'
      type = 'win32'
      version = '1.0.0.1'

      [file]
      name = 'helper-tool.exe'

      [trustInfo]
      xmlns = 'urn:schemas-microsoft-com:asm.v2'
      security.requestedPrivileges = [
        {
          requestedExecutionLevel = { level = 'requireAdministrator', uiAccess = false }
        }
      ]
      """

    let manifest = try TOMLDecoder().decode(
      WindowsApplicationManifest.self,
      from: partialManifest
    )

    #expect(manifest == generateWindowsManifest())
  }

  @Test func testCreationWorkflow() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("HelloWorld")

    if directory.exists() {
      try FileManager.default.removeItem(at: directory)
    }

    var creationArguments = ["create", "HelloWorld", "-d", directory.path]

    #if os(macOS)
      // Without this, the build will fail due to a missing minimum deployment version.
      creationArguments += ["-t", "SwiftUI"]
    #endif

    // Ensure creation succeeds
    await SwiftBundler.main(creationArguments)

    // Ensure fresh project builds
    await SwiftBundler.main(["bundle", "HelloWorld", "-d", directory.path, "-o", directory.path])

    // Ensure idempotence
    await SwiftBundler.main(["bundle", "HelloWorld", "-d", directory.path, "-o", directory.path])
  }

  @Test(.bug("https://github.com/moreSwift/swift-bundler/issues/154"))
  func testRunCommandSucceeds() async throws {
    let fixture = Bundle.module.bundleURL / "Fixtures/HelloWorld"

    // Ensure run command succeeds
    await SwiftBundler.main(["run", "HelloWorld", "-d", fixture.path])
  }

  @Test(.bug("https://github.com/moreSwift/swift-bundler/issues/120"))
  func testManifestParsingBug120() async throws {
    try await withFixture("ManifestParsingBug_Issue120") { fixture in
      await SwiftBundler.main(["bundle", "-d", fixture.path])
    }
  }

  @Test func testHexParsing() throws {
    #expect(Array(fromHex: "AB5D87") == [0xab, 0x5d, 0x87])
    #expect(Array(fromHex: "ab5d87") == [0xab, 0x5d, 0x87])
    #expect(Array(fromHex: "ef917") == nil)
    #expect(Array(fromHex: "ef917g") == nil)
  }

  @Test("Ensures that a project with a basic Makefile subproject builds and runs")
  func testMakefileSubproject() async throws {
    try await withFixture("MakefileBuilder") { fixture in
      await SwiftBundler.main(["run", "-d", fixture.path])
    }
  }

  @Test(
    """
    Ensures that inline builders still work for backwards compatibility even \
    though they've been deprecated
    """
  )
  func testDeprecatedInlineBuilderMakefileSubproject() async throws {
    try await withFixture("DeprecatedInlineMakefileBuilder") { fixture in
      await SwiftBundler.main(["run", "-d", fixture.path])
    }
  }

  @Test func testLibraryWithHelperExecutable() async throws {
    try await withFixture("LibraryProjectDependencies") { fixture in
      await SwiftBundler.main(["run", "-d", fixture.path])
    }
  }

  #if os(macOS)
    /// This test app depends on both a plain dynamic library and a framework.
    @Test func testDarwinDynamicDependencyCopying() async throws {
      let app = "DarwinDynamicDependencies"
      try await withFixture(app) { fixture in
        await SwiftBundler.main(["bundle", "-d", fixture.path])
        let outputPath = fixture / ".build/bundler/apps/\(app)/\(app).app"

        let sparkle = outputPath / "Contents/Frameworks/Sparkle.framework"
        #expect(sparkle.exists(), "didn't copy framework")

        let library = outputPath / "Contents/Libraries/libLibrary.dylib"
        #expect(library.exists(), "didn't copy dynamic library")

        // Move the app and remove the debug directory to ensure that the app
        // is relocatable and independent of any compile-time artifacts. See
        // issue #85.
        let appCopy = fixture / "\(app).app"
        try? FileManager.default.removeItem(at: appCopy)
        try FileManager.default.copyItem(at: outputPath, to: appCopy)
        try FileManager.default.removeItem(at: fixture / ".build")

        // Ensure that the copied dynamic dependencies are usable by the app.
        let executable = appCopy / "Contents/MacOS/\(app)"
        let process = Process.create(executable.path)
        let output = try await process.getOutput()
        #expect(
          output
          ==
          """
          2 + 3 = 5
          1.0.0 > 1.0.1 = false

          """
        )
      }
    }
  #endif
}
