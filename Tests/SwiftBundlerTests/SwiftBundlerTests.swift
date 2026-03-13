import Testing
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
