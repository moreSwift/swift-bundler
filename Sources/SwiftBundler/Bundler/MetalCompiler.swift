import Foundation

/// A utility for compiling metal shader source files.
enum MetalCompiler {
  /// Compiles any metal shaders present in a directory into a `default.metallib` file (in the same directory).
  /// - Parameters:
  ///   - directory: The directory to compile shaders from.
  ///   - platform: The platform to compile for.
  ///   - platformVersion: The platform version to target during compilation.
  ///   - keepSources: If `false`, the sources will get deleted after compilation.
  static func compileMetalShaders(
    in directory: URL,
    for platform: Platform,
    platformVersion: String,
    keepSources: Bool
  ) async throws(Error) {
    guard
      let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [])
    else {
      throw Error(.failedToEnumerateShaders(directory: directory))
    }

    var shaderSources: [URL] = []
    for case let file as URL in Array(enumerator) where file.pathExtension == "metal" {
      shaderSources.append(file)
    }

    guard !shaderSources.isEmpty else {
      return
    }

    log.info("Compiling metal shaders")

    _ = try await compileMetalShaders(
      shaderSources,
      to: directory,
      for: platform,
      platformVersion: platformVersion
    )

    if !keepSources {
      for source in shaderSources {
        try FileManager.default.removeItem(
          at: source,
          errorMessage: ErrorMessage.failedToDeleteShaderSource
        )
      }
    }
  }

  /// Compiles a list of metal source files into a `metallib` file.
  /// - Parameters:
  ///   - sources: The source files to comile.
  ///   - destination: The directory to output `default.metallib` to.
  ///   - platform: The platform to compile for.
  ///   - platformVersion: The platform version to target during compilation.
  /// - Returns: Returns the location of the resulting `metallib`.
  static func compileMetalShaders(
    _ sources: [URL],
    to destination: URL,
    for platform: Platform,
    platformVersion: String
  ) async throws(Error) -> URL {
    // Create a temporary directory for compilation
    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("metal_compilation-\(UUID().uuidString)")
    let archive = tempDirectory.appendingPathComponent("default.metal-ar")

    try FileManager.default.createDirectory(
      at: tempDirectory,
      errorMessage: ErrorMessage.failedToCreateTemporaryCompilationDirectory
    )

    // Compile the shaders into `.air` files
    let airFiles = try await sources.typedAsyncMap { (shaderSource) throws(Error) -> URL in
      let outputFileName = shaderSource.deletingPathExtension()
        .appendingPathExtension("air").lastPathComponent
      let outputFile = tempDirectory.appendingPathComponent(outputFileName)

      try await compileShader(
        shaderSource,
        to: outputFile,
        for: platform,
        platformVersion: platformVersion
      )

      return outputFile
    }

    // Combine the compiled shaders into a `.metal-ar` archive
    try await createArchive(at: archive, from: airFiles, for: platform)

    // Convert the `metal-ar` archive into a `metallib` library
    let library = destination.appendingPathComponent("default.metallib")
    try await createLibrary(at: library, from: archive, for: platform)

    return library
  }

  /// Compiles a metal shader file into an `air` file.
  /// - Parameters:
  ///   - shader: The shader file to compile.
  ///   - outputFile: The resulting `air` file.
  ///   - platform: The platform to build for.
  ///   - platformVersion: The platform version to target during compilation.
  static func compileShader(
    _ shader: URL,
    to outputFile: URL,
    for platform: Platform,
    platformVersion: String
  ) async throws(Error) {
    var arguments = [
      "-sdk", platform.sdkName, "metal",
      "-o", outputFile.path,
      "-c", shader.path,
      "-gline-tables-only", // TODO: disable these in distribution builds
      "-frecord-sources",
    ]

    switch platform {
      case .macOS:
        arguments.append("-mmacosx-version-min=\(platformVersion)")
      case .iOS:
        arguments.append("-mios-version-min=\(platformVersion)")
      default:
        // TODO: Figure out whether any other platforms require/have a minimum platform version option
        break
    }

    let process = Process.create(
      "/usr/bin/xcrun",
      arguments: arguments,
      runSilentlyWhenNotVerbose: false
    )

    do {
      try await process.runAndWait()
    } catch {
      throw Error(.failedToCompileShader(shader), cause: error)
    }
  }

  /// Creates a metal archive (a `metal-ar` file) from a list of `air` files
  /// (which can be created by ``compileShader(_:outputDirectory:)``).
  /// - Parameters:
  ///   - archive: The resulting `metal-ar` file.
  ///   - airFiles: The air files to create an archive from.
  ///   - platform: The platform to archive for.
  static func createArchive(
    at archive: URL,
    from airFiles: [URL],
    for platform: Platform
  ) async throws(Error) {
    let process = Process.create(
      "/usr/bin/xcrun",
      arguments: [
        "-sdk", platform.sdkName, "metal-ar",
        "rcs", archive.path,
      ] + airFiles.map(\.path)
    )

    do {
      try await process.runAndWait()
    } catch {
      throw Error(.failedToCreateMetalArchive, cause: error)
    }
  }

  /// Creates a metal library from a metal archive.
  /// - Parameters:
  ///   - library: The output file location.
  ///   - archive: The archive to convert.
  ///   - platform: The platform to create the library for.
  static func createLibrary(
    at library: URL,
    from archive: URL,
    for platform: Platform
  ) async throws(Error) {
    let process = Process.create(
      "/usr/bin/xcrun",
      arguments: [
        "-sdk", platform.sdkName, "metallib",
        archive.path,
        "-o", library.path,
      ]
    )

    try await Error.catch(withMessage: .failedToCreateMetalLibrary) {
      try await process.runAndWait()
    }
  }
}
