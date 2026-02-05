import Foundation
import Version

/// Inserts metadata into executable files.
///
/// Swift Bundler inserts metadata at the end of your main executable file
/// after compilation. The format is intended to be simple and portable to
/// ensure that even if someone isn't using the Swift Bundler runtime they
/// can easily parse the metadata at runtime. If the metadata format ever
/// gets extended, it will be extended in such a way that current metadata
/// remains valid, and future metadata is backwards compatible.
enum MetadataInserter {
  /// Metadata appended to the end of executable files built with Swift
  /// Bundler.
  struct Metadata: Codable {
    /// The app's identifier.
    var appIdentifier: String
    /// The app's version.
    var appVersion: Version
    /// Additional user-defined metadata.
    var additionalMetadata: [String: MetadataValue]
  }

  enum CompiledMetadata {
    case objectFile(URL)
    case staticLibrary(URL, name: String)
  }

  /// Generates an app's metadata from its configuration.
  static func metadata(for configuration: AppConfiguration.Flat) -> Metadata {
    Metadata(
      appIdentifier: configuration.identifier,
      appVersion: configuration.version,
      additionalMetadata: configuration.metadata
    )
  }

  /// Generates a state library containing the given metadata. The file name of
  /// the library is platform dependent and is set to ensure that `-lmetadata`
  /// is sufficient to link against the metadata library.
  /// - Returns: The path to the produced object file.
  static func compileMetadata(
    in directory: URL,
    for metadata: Metadata,
    architectures: [BuildArchitecture],
    platform: Platform
  ) async throws(Error) -> CompiledMetadata {
    let codeFile = directory / "metadata.swift"
    let data = try Error.catch(withMessage: .failedToEncodeMetadata) {
      try JSONEncoder().encode(metadata)
    }

    // We insert our JSON encoded metadata as the first entry in an array of
    // byte arrays, because we want to support binary attachments in future
    // (for embedding arbitrary resource files in executables).
    let array = Array(data)
    let code = """
      private(set) var metadata: [[UInt8]] = [[\(array.map(\.description).joined(separator: ", "))]]

      @_cdecl("_getSwiftBundlerMetadata")
      func getSwiftBundlerMetadata() -> UnsafeRawPointer? {
          return withUnsafeMutablePointer(to: &metadata) { pointer in
              UnsafeRawPointer(pointer)
          }
      }

      @_silgen_name("sbun_getMetadata")
      func getSwiftBundlerMetadataNew() -> [[UInt8]] {
          return metadata
      }
      """

    try Error.catch(withMessage: .failedToWriteMetadataCodeFile) {
      try code.write(to: codeFile)
    }

    if architectures.count > 1 || platform.isApplePlatform {
      let name = "metadata"
      let universalStaticLibrary = directory / "lib\(name).a"
      try await compileMetadataCodeFile(
        codeFile,
        toUniversalStaticLibrary: universalStaticLibrary,
        scratchDirectory: directory,
        platform: platform,
        architectures: architectures
      )
      return .staticLibrary(universalStaticLibrary, name: name)
    } else {
      let objectFile = directory / "metadata.o"
      try await compileMetadataCodeFile(
        codeFile,
        to: objectFile,
        platform: platform,
        architecture: architectures[0]
      )
      return .objectFile(objectFile)
    }
  }

  private static func compileMetadataCodeFile(
    _ codeFile: URL,
    toUniversalStaticLibrary universalStaticLibrary: URL,
    scratchDirectory: URL,
    platform: Platform,
    architectures: [BuildArchitecture]
  ) async throws(Error) {
    let objectFiles = architectures.map { architecture in
      scratchDirectory / "metadata-\(architecture).o"
    }

    for (objectFile, architecture) in zip(objectFiles, architectures) {
      try await compileMetadataCodeFile(
        codeFile,
        to: objectFile,
        platform: platform,
        architecture: architecture
      )
    }

    let staticLibraries = architectures.map { architecture in
      scratchDirectory / "metadata-\(architecture).a"
    }

    for (staticLibraryFile, objectFile) in zip(staticLibraries, objectFiles) {
      try await Error.catch(withMessage: .failedToCreateStaticLibrary) {
        try await Process.create(
          "ar",
          arguments: ["r", staticLibraryFile.path, objectFile.path]
        ).runAndWait()
      }
    }

    try await Error.catch(withMessage: .failedToCreateUniversalStaticLibrary) {
      try await Process.create(
        "lipo",
        arguments: [
          "-o", universalStaticLibrary.path, "-create"
        ] + staticLibraries.map(\.path)
      ).runAndWait()
    }
  }

  static func compileMetadataCodeFile(
    _ codeFile: URL,
    to objectFile: URL,
    platform: Platform,
    architecture: BuildArchitecture
  ) async throws(Error) {
    var platformArguments: [String] = []

    if let platform = platform.asApplePlatform {
      let target = try Error.catch {
        try platform.platform.targetTriple(
          withArchitecture: architecture,
          andPlatformVersion: platform.minimumSwiftSupportedVersion
        )
      }
      platformArguments += ["-target", target.description]

      let sdkPath = try await Error.catch(withMessage: .failedToGetSDKPath) {
        try await SwiftPackageManager.getLatestSDKPath(for: platform.platform)
      }

      platformArguments += ["-sdk", sdkPath]
    }

    try await Error.catch(withMessage: .failedToCompileMetadataCodeFile) {
      try await Process.create(
        "swiftc",
        arguments: [
          "-parse-as-library", "-c",
          "-o", objectFile.path, codeFile.path,
        ] + platformArguments,
        runSilentlyWhenNotVerbose: false
      ).runAndWait()
    }
  }

  /// Additional SwiftPM arguments to use when inserting metadata into a build.
  /// Includes flags to enable conditionally compiled parts of the Swift Bundler
  /// runtime.
  static func additionalSwiftPackageManagerArguments(
    toInsert compiledMetadata: CompiledMetadata
  ) -> [String] {
    switch compiledMetadata {
      case .objectFile(let objectFile):
        return [
          "-Xlinker", objectFile.path,
          "-Xswiftc", "-DSWIFT_BUNDLER_METADATA",
          "-Xcc", "-DSWIFT_BUNDLER_METADATA",
        ]
      case .staticLibrary(let staticLibrary, let name):
        return [
          "-Xlinker", "-l\(name)",
          "-Xlinker", "-L\(staticLibrary.deletingLastPathComponent().path)",
          "-Xswiftc", "-DSWIFT_BUNDLER_METADATA",
          "-Xcc", "-DSWIFT_BUNDLER_METADATA",
        ]
    }
  }

  /// Additional xcodebuild arguments to use when inserting metadata into a build.
  /// Includes flags to enable conditionally compiled parts of the Swift Bundler
  /// runtime.
  static func additionalXcodebuildArguments(
    toInsert compiledMetadata: CompiledMetadata
  ) -> [String] {
    switch compiledMetadata {
      case .objectFile(let objectFile):
        return [
          "OTHER_LDFLAGS=\(objectFile.path) ${OTHER_LDFLAGS}",
          "OTHER_SWIFT_FLAGS=-DSWIFT_BUNDLER_METADATA ${OTHER_SWIFT_FLAGS}",
          "OTHER_CFLAGS=-DSWIFT_BUNDLER_METADATA ${OTHER_CFLAGS}",
        ]
      case .staticLibrary(let staticLibrary, let name):
        let directory = staticLibrary.deletingLastPathComponent().path
          .replacingOccurrences(of: " ", with: "\\ ")
        return [
          "OTHER_LDFLAGS=-l\(name) -L\(directory) ${OTHER_LDFLAGS}",
          "OTHER_SWIFT_FLAGS=-DSWIFT_BUNDLER_METADATA ${OTHER_SWIFT_FLAGS}",
          "GCC_PREPROCESSOR_DEFINITIONS=SWIFT_BUNDLER_METADATA=1 ${GCC_PREPROCESSOR_DEFINITIONS}",
        ]
    }
  }
}
