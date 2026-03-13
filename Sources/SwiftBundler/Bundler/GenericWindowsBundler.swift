import Foundation
import Ico
import ImageFormats
import ZIPFoundation

/// A bundler targeting generic Windows systems. Arranges executables, resources,
/// and dynamic libraries into a standard directory layout.
///
/// This bundler is great to use during development as it provides a realistic
/// runtime environment while keeping bundling overhead low, allowing for quick
/// iteration.
///
/// The other Windows bundlers provided by Swift Bundler rely on this bundler to
/// do all of the heavy lifting. After running the generic bundler they simply
/// take the output and bundle it up into an often distro-specific package file
/// or standalone executable.
enum GenericWindowsBundler: Bundler {
  static let outputIsRunnable = true

  struct Context {}

  private static let resourceHackerDownloadURL =
    URL(string: "https://www.angusj.com/resourcehacker/resource_hacker.zip")!

  private static let dllBundlingAllowList: [String] = [
    "swiftCore",
    "swiftCRT",
    "swiftDispatch",
    "swiftDistributed",
    "swiftObservation",
    "swiftRegexBuilder",
    "swiftRemoteMirror",
    "swiftSwiftOnoneSupport",
    "swiftSynchronization",
    "swiftWinSDK",
    "Foundation",
    "FoundationXML",
    "FoundationNetworking",
    "FoundationEssentials",
    "FoundationInternationalization",
    "BlocksRuntime",
    "_FoundationICU",
    "_InternalSwiftScan",
    "_InternalSwiftStaticMirror",
    "swift_Concurrency",
    "swift_RegexParser",
    "swift_StringProcessing",
    "swift_Differentiation",
    "concrt140",
    "msvcp140",
    "msvcp140_1",
    "msvcp140_2",
    "msvcp140_atomic_wait",
    "msvcp140_codecvt_ids",
    "vccorlib140",
    "vcruntime140",
    "vcruntime140_1",
    "vcruntime140_threads",
    "dispatch",
  ].map { "\($0).dll".lowercased() }

  static func computeContext(
    context: BundlerContext,
    command: BundleCommand,
    manifest: PackageManifest
  ) throws(Error) -> Context {
    // GenericWindowsBundler's additional context only exists to allow other
    // bundlers to configure it when building on top of it, so for command-line
    // usage we can just use the defaults.
    Context()
  }

  static func intendedOutput(
    in context: BundlerContext,
    _ additionalContext: Context
  ) -> BundlerOutputStructure {
    let bundle = context.outputDirectory
      .appendingPathComponent("\(context.appName).generic")
    let structure = BundleStructure(
      at: bundle,
      forApp: context.appName,
      withIdentifier: context.appConfiguration.identifier
    )
    return structure.asOutputStructure
  }

  static func prepareAdditionalSPMBuildArguments(
    _ context: BundlerContext,
    _ additionalContext: Context,
    dryRun: Bool
  ) async throws(Error) -> [String] {
    guard let iconPath = context.appConfiguration.icon else {
      return []
    }

    if !dryRun {
      log.info("Compiling icon")

      let icoFile = try prepareIcon(iconPath: iconPath, context: context)

      // Create rc file
      let rcFile = context.outputDirectory / "icon.rc"

      // Approach inspired by https://github.com/mxre/winres/pull/12
      // I haven't escaped non-printable ASCII characters as hex escapes because I
      // figured they shouldn't be in Windows paths, but if they are, we should e.g.
      // escape the byte 0x81 as '\x81'.
      let escapedPath = icoFile.path
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\"\"")
        .replacingOccurrences(of: "\t", with: "\\t")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\'", with: "\\'")
      let rcFileContent = """
        MAINICON ICON "\(escapedPath)"
        """

      try Error.catch {
        try rcFileContent.write(to: rcFile)
      }

      // Compile rc file
      let process = Process.create(
        "rc",
        arguments: ["-nologo", rcFile.path],
        directory: rcFile.deletingLastPathComponent()
      )

      try await Error.catch {
        try await process.runAndWait()
      }
    }

    let resourceFile = context.outputDirectory / "icon.res"
    return [
      "-Xlinker", resourceFile.path
    ]
  }

  /// Prepares an 'ico' version of the app's icon.
  /// - Parameter iconPath: The icon's path as given in the configuration file,
  ///   i.e. relative to the package directory.
  static func prepareIcon(
    iconPath: String,
    context: BundlerContext,
    skipIfPresent: Bool = false
  ) throws(Error) -> URL {
    let icon = context.packageDirectory / iconPath

    let icoFile = context.outputDirectory / "icon.ico"
    if skipIfPresent && icoFile.exists() {
      return icoFile
    }

    // Convert to ico
    let image = try Error.catch(withMessage: .failedToLoadIcon(icon)) {
      let imageData = try Data(contentsOf: icon)
      return try Image<RGBA>.load(from: Array(imageData))
    }.convert(to: ARGB.self)

    // NB: If we put the images in order of decreasing size instead of
    //   increasing size then the Apps & features screen doesn't show
    //   MSI icons correctly (it shows them blank).
    let scaledImages = [16, 24, 32, 48, 256].map { dimension in
      // TODO(stackotter): Support upscaling?
      image.linearlyDownscale(toWidth: dimension, height: dimension)
    }

    let ico = Ico(images: scaledImages)
    let icoData = try Error.catch(withMessage: .failedToEncodeIco) {
      try ico.encode()
    }

    try Error.catch {
      try Data(icoData).write(to: icoFile)
    }

    return icoFile
  }

  static func bundle(
    _ context: BundlerContext,
    _ additionalContext: Context
  ) async throws(Error) -> BundlerOutputStructure {
    try await bundle(context, additionalContext).asOutputStructure
  }

  static func bundle(
    _ context: BundlerContext,
    _ additionalContext: Context
  ) async throws(Error) -> BundleStructure {
    let root = intendedOutput(in: context, additionalContext).bundle
    let appBundleName = root.lastPathComponent

    log.info("Bundling '\(appBundleName)'")

    let executableArtifact = context.executableArtifact

    let structure = BundleStructure(
      at: root,
      forApp: context.appName,
      withIdentifier: context.appConfiguration.identifier
    )
    try structure.createDirectories()

    try copyExecutable(at: executableArtifact, to: structure.mainExecutable)

    if let codeSigningContext = context.windowsCodeSigningContext {
      log.info("Signing executable")
      try await Error.catch {
        try await WindowsCodeSigner.signFile(
          structure.mainExecutable,
          context: codeSigningContext
        )
      }
    }

    try await copyDependencies(
      structure: structure,
      context: context,
      additionalContext: additionalContext
    )

    try copyResources(
      from: context.productsDirectory,
      to: structure.resources
    )

    return structure
  }

  // MARK: Private methods

  /// Sets the icon of an executable file to the given icon (supports PNG, JPEG, WebP).
  ///
  /// > Important: Currently unused, but figured it was useful code to have around
  /// >   in case future SwiftPM versions fix the linker behaviour (i.e. trailing DWARF
  /// >   data) that stopped us from using this approach.
  private static func setExecutableIcon(
    of executable: URL,
    to icon: URL
  ) async throws(Error) {
    let image = try Error.catch(withMessage: .failedToLoadIcon(icon)) {
      let imageData = try Data(contentsOf: icon)
      return try Image<RGBA>.load(from: Array(imageData))
    }.convert(to: ARGB.self)

    let ico = Ico(images: [image])
    let icoData = try Error.catch(withMessage: .failedToEncodeIco) {
      try ico.encode()
    }

    let icoFile = FileManager.default.temporaryDirectory / "\(UUID().uuidString).ico"
    try Error.catch {
      try Data(icoData).write(to: icoFile)
    }

    defer {
      try? FileManager.default.removeItem(at: icoFile)
    }

    let resourceHacker = try ensureResourceHacker()
    let process = Process.create(
      resourceHacker.path,
      arguments: [
        "-open", executable.path, "-save", executable.path,
        "-action", "addoverwrite",
        "-res", icoFile.path,
        "-mask", "ICONGROUP,APP"
      ]
    )

    try await Error.catch(withMessage: .failedToRunResourceHacker) {
      try await process.runAndWait()
    }
  }

  /// Ensures that Resource Hacker is present, by downloading it if it isn't,
  /// and returns the location of the Resource Hacker tool on success.
  ///
  /// > Important: Currently unused, but figured it was useful code to have around
  /// >   in case future SwiftPM versions fix the linker behaviour (i.e. trailing DWARF
  /// >   data) that stopped us from using this approach.
  private static func ensureResourceHacker() throws(Error) -> URL {
    let toolsDirectory = try Error.catch {
      try System.getToolsDirectory()
    }

    let resourceHacker = toolsDirectory / "ResourceHacker.exe"
    if resourceHacker.exists() {
      return resourceHacker
    }

    log.info("Downloading Resource Hacker")
    log.debug("Downloading Resource Hacker from \(resourceHackerDownloadURL.absoluteString)")
    let uuid = UUID().uuidString
    let temp = FileManager.default.temporaryDirectory
    let resourceHackerZip = temp / "ResourceHacker-\(uuid).zip"
    let resourceHackerDirectory = temp / "ResourceHacker-\(uuid)"
    try Error.catch(withMessage: .failedToDownloadResourceHacker) {
      let content = try Data(contentsOf: resourceHackerDownloadURL)
      try content.write(to: resourceHackerZip)
      try FileManager.default.unzipItem(at: resourceHackerZip, to: resourceHackerDirectory)
    }

    defer {
      try? FileManager.default.removeItem(at: resourceHackerZip)
    }

    let executable = resourceHackerDirectory / "ResourceHacker.exe"
    let message = ErrorMessage.failedToLocateResourceHackerExecutable(
      expectedLocation: executable
    )

    try Error.catch(withMessage: message) {
      try FileManager.default.copyItem(
        at: executable,
        to: resourceHacker
      )
    }

    // Only remove the directory if we successfully locate the executable, to make
    // debugging a little easier
    try? FileManager.default.removeItem(at: resourceHackerDirectory)

    return resourceHacker
  }

  private static func copyDependencies(
    structure: BundleStructure,
    context: BundlerContext,
    additionalContext: Context
  ) async throws(Error) {
    // Copy all executable dependencies into the bundle next to the main
    // executable
    for (reference, dependency) in context.builtDependencies {
      guard dependency.product.type == .executable else {
        continue
      }

      for artifact in dependency.artifacts {
        let source = artifact.location
        let destination = structure.modules / source.lastPathComponent
        do {
          try FileManager.default.copyItem(
            at: source,
            to: destination
          )
        } catch {
          throw Error(.failedToCopyExecutableDependency(reference), cause: error)
        }

        if artifact.location.pathExtension == "exe",
          let codeSigningContext = context.windowsCodeSigningContext
        {
          try await Error.catch {
            try await WindowsCodeSigner.signFile(
              destination,
              context: codeSigningContext
            )
          }
        }
      }
    }
    
    log.info("Copying dynamic libraries (and Swift runtime)")
    try await copyDynamicLibraryDependencies(
      of: structure.mainExecutable,
      to: structure.modules,
      productsDirectory: context.productsDirectory
    )
  }

  /// Copies dynamic library dependencies of the specified module to the given
  /// destination folder. Discovers dependencies recursively with `dumpbin`.
  /// Currently just ignores any dependencies that it can't locate (since there
  /// are many dlls that we don't want to distribute in the first place, such as
  /// ones that come with Windows).
  /// - Returns: The original URLs of copied dependencies.
  private static func copyDynamicLibraryDependencies(
    of module: URL,
    to destination: URL,
    productsDirectory: URL
  ) async throws(Error) {
    let productsDirectory = productsDirectory.actuallyResolvingSymlinksInPath()

    let dlls = try await enumerateDynamicLibraryDependencies(
      module: module,
      productsDirectory: productsDirectory
    )

    for dll in dlls {
      let destinationFile = destination / dll.lastPathComponent

      // We've already copied this dll across so we don't need to copy it or
      // recurse to its dependencies.
      guard !destinationFile.exists() else {
        continue
      }

      // Resolve symlinks in case the library itself is a symlinnk (we want
      // to copy the actual library not the symlink).
      let resolvedSourceFile = dll.actuallyResolvingSymlinksInPath()

      log.debug("Copying '\(dll.path)'")
      let pdbFile = resolvedSourceFile.replacingPathExtension(with: "pdb")
      try FileManager.default.copyItem(
        at: resolvedSourceFile,
        to: destinationFile,
        errorMessage: ErrorMessage.failedToCopyDLL
      )

      if pdbFile.exists() {
        // Copy dll's pdb file if present
        let destinationPDBFile = destinationFile.replacingPathExtension(
          with: "pdb"
        )
        try FileManager.default.copyItem(
          at: pdbFile,
          to: destinationPDBFile,
          errorMessage: ErrorMessage.failedToCopyPDB
        )
      }

      // Recurse to ensure that we copy indirect dependencies of the main
      // executable as well as the direct ones that `dumpbin` lists.
      try await copyDynamicLibraryDependencies(
        of: resolvedSourceFile,
        to: destination,
        productsDirectory: productsDirectory
      )
    }
  }

  /// Enumerates the non-system DLLs depended on by the given module.
  private static func enumerateDynamicLibraryDependencies(
    module: URL,
    productsDirectory: URL
  ) async throws(Error) -> [URL] {
    let output: String
    do {
      output = try await Process.create(
        "dumpbin",
        arguments: ["/DEPENDENTS", module.path],
        runSilentlyWhenNotVerbose: false
      ).getOutput()
    } catch {
      throw Error(.failedToEnumerateDynamicDependencies, cause: error)
    }

    let lines = output.split(
      omittingEmptySubsequences: false,
      whereSeparator: \.isNewline
    )
    let headingLine = "  Image has the following dependencies:"
    guard let headingIndex = lines.firstIndex(of: headingLine[...]) else {
      let message = ErrorMessage.failedToParseDumpbinOutput(
        output: output,
        message: "Couldn't find section heading"
      )
      throw Error(message)
    }

    let startIndex = headingIndex + 2
    guard let endIndex = lines[startIndex...].firstIndex(of: "") else {
      let message = ErrorMessage.failedToParseDumpbinOutput(
        output: output,
        message: "Couldn't find end of section"
      )
      throw Error(message)
    }

    let dllNames = lines[startIndex..<endIndex].map { line in
      String(line.trimmingCharacters(in: .whitespaces))
    }

    let dlls = try dllNames.compactMap { (dllName) throws(Error) -> URL? in
      log.debug("Resolving '\(dllName)'")
      return try resolveDLL(dllName, productsDirectory: productsDirectory)
    }

    return dlls
  }

  private static func resolveDLL(
    _ name: String,
    productsDirectory: URL
  ) throws(Error) -> URL? {
    // If the dll exists next to the `exe` it's a product of the build
    // and we should copy it across.
    let guess = productsDirectory / name
    if guess.exists() {
      return guess
    }

    // If the dll isn't a product of the SwiftPM build, we should only
    // copy it across if it's known (cause there are many DLLs, such as
    // ones shipped with Windows, that we shouldn't be distributing with
    // apps).
    guard dllBundlingAllowList.contains(name.lowercased()) else {
      return nil
    }

    // Parse the PATH environment variable.
    let pathVar = ProcessInfo.processInfo.environment["Path"] ?? ""
    let pathDirectories = pathVar.split(separator: ";").map { path in
      URL(fileURLWithPath: String(path))
    }

    // Search each directory on the path for the DLL we're looking for.
    guard
      let dll = pathDirectories.map({ directory in
        directory / name
      }).first(where: { (dll: URL) in
        dll.exists()
      })
    else {
      throw Error(.failedToResolveDLLName(name))
    }

    return dll
  }

  /// Copies any resource bundles produced by the build system and changes
  /// their extension from `.resources` to `.bundle` for consistency with
  /// bundling on Apple platforms.
  private static func copyResources(
    from sourceDirectory: URL,
    to destinationDirectory: URL
  ) throws(Error) {
    let contents = try FileManager.default.contentsOfDirectory(
      at: sourceDirectory,
      errorMessage: ErrorMessage.failedToEnumerateResourceBundles
    )

    let bundles = contents.filter { file in
      file.pathExtension == "resources"
        && file.exists(withType: .directory)
    }

    for bundle in bundles {
      log.info("Copying resource bundle '\(bundle.lastPathComponent)'")

      let bundleName = bundle.deletingPathExtension().lastPathComponent

      let destinationBundle: URL
      if bundleName == "swift-windowsappsdk_CWinAppSDK" {
        // swift-windowsappsdk expects the bootstrap dll to be at the
        // location that SwiftPM puts it at, so we mustn't change the
        // extension from `.resources` to `.bundle` in this case.
        destinationBundle = destinationDirectory / "\(bundleName).resources"
      } else {
        destinationBundle = destinationDirectory / "\(bundleName).bundle"
      }

      try FileManager.default.copyItem(
        at: bundle,
        to: destinationBundle,
        errorMessage: ErrorMessage.failedToCopyResourceBundle
      )
    }
  }

  /// Copies the built executable into the app bundle. Also copies the
  /// executable's corresponding `.pdb` debug info file if found.
  /// - Parameters:
  ///   - source: The location of the built executable.
  ///   - destination: The target location of the built executable (the file not the directory).
  private static func copyExecutable(
    at source: URL,
    to destination: URL
  ) throws(Error) {
    log.info("Copying executable")

    let pdbFile = source.replacingPathExtension(with: "pdb")
    try FileManager.default.copyItem(
      at: source,
      to: destination,
      errorMessage: ErrorMessage.failedToCopyExecutable
    )

    if pdbFile.exists() {
      let pdbDestination = destination.replacingPathExtension(with: "pdb")
      try FileManager.default.copyItem(
        at: source,
        to: pdbDestination,
        errorMessage: ErrorMessage.failedToCopyPDB
      )
    }
  }
}
