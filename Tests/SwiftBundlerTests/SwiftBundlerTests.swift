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

  @Test(.bug("https://github.com/moreSwift/swift-bundler/issues/120"))
  func testManifestParsingBug120() async throws {
      let fixture = Bundle.module.bundleURL / "Fixtures/ManifestParsingBug_Issue120"
      await SwiftBundler.main(["bundle", "-d", fixture.path])
  }

  @Test func testHexParsing() throws {
    #expect(Array(fromHex: "AB5D87") == [0xab, 0x5d, 0x87])
    #expect(Array(fromHex: "ab5d87") == [0xab, 0x5d, 0x87])
    #expect(Array(fromHex: "ef917") == nil)
    #expect(Array(fromHex: "ef917g") == nil)
  }

  #if os(macOS)
    /// This test app depends on both a plain dynamic library and a framework.
    @Test func testDarwinDynamicDependencyCopying() async throws {
      let app = "DarwinDynamicDependencies"
      let fixture = Bundle.module.bundleURL.appendingPathComponent("Fixtures/\(app)")
      await SwiftBundler.main(["bundle", "-d", fixture.path])
      let outputPath = fixture / ".build/bundler/\(app).app"

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
  #endif
}
