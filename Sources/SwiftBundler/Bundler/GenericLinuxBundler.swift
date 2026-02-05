import Foundation
import Parsing

/// A bundler targeting generic Linux systems. Arranges executables, resources,
/// and dynamic libraries into a standard directory layout based off the
/// Filesystem Hierarchy Standard that Linux systems generally follow.
///
/// This bundler is great to use during development as it provides a realistic
/// runtime environment while keeping bundling overhead low, allowing for quick
/// iteration.
///
/// The other Linux bundlers provided by Swift Bundler rely on this bundler to
/// do all of the heavy lifting. After running the generic bundler they simply
/// take the output and bundle it up into an often distro-specific package file
/// or standalone executable.
enum GenericLinuxBundler: Bundler {
  static let outputIsRunnable = true
  static let requiresBuildAsDylib = false

  struct Context {
    /// Used in log messages to avoid exposing that everything's just the
    /// generic Linux bundler all the way down. Doesn't affect the fact
    /// that the generic bundler's output will have the `.generic` file
    /// extension. It's up to other bundlers to transform that output
    /// into their desired output format.
    var cosmeticBundleName: String?
    /// The full path to the bundle when installed on a system. Used when
    /// generating the app's `.desktop` file. Useful for packaging bundlers
    /// such as ``RPMBundler`` that know where the app will get installed
    /// on the system. For example, a value of `/` would mean that the app
    /// has been installed to the standard Linux locations, with the
    /// executable going to `/usr/bin` etc. Defaults to `/`.
    var installationRoot = URL(fileURLWithPath: "/")
  }

  /// A parser for the output of ldd. Parses a single line.
  private static let lddLineParser = Parse {
    PrefixThrough(" => ")
    PrefixUpTo(" (")
    Rest<Substring>()
  }.map { (_: Substring, path: Substring, _: Substring) in
    String(path)
  }

  /// The list of dynamic libraries that are allowed to get bundled into
  /// the final app bundle. The reason we need an allow list in the first
  /// place is that a large proportion of dynamic libraries cause issues
  /// when distributed to different platforms (such as Gtk). So for now
  /// we just stick to bundling Swift's dependencies. Ideally we'd
  /// just generate this list from the Swift toolchain but we won't always
  /// know which Swift toolchain was used to build the binary etc. And we
  /// want to bundle `libcurl` and `libxml` as well since they're both
  /// dependencies of the Swift runtime but they're not included in
  /// the runtime itself.
  ///
  /// We don't bundle libc because that can cause all kinds of weird issues;
  /// the main one being that any external dependencies of the app are forced
  /// to use the same libc as the main executable, so if the user's machine
  /// has a different enough libc version and the main executable depends on
  /// external dependencies, then you'll probably get segfaults.
  private static let dynamicLibraryBundlingAllowList: [String] = [
    "libswiftCore",
    "libswiftGlibc",
    "libswiftDispatch",
    "libswiftDistributed",
    "libswiftObservation",
    "libswiftRegexBuilder",
    "libswiftRemoteMirror",
    "libswiftSynchronization",
    "libswiftSwiftOnoneSupport",
    "libBlocksRuntime",
    "libdispatch",
    "libswift_Volatile",
    "libswift_Concurrency",
    "libswift_RegexParser",
    "libswift_StringProcessing",
    "libswift_Backtracing",
    "libswift_Builtin_float",
    "libswift_Differentiation",
    "lib_FoundationICU",
    "lib_InternalSwiftScan",
    "lib_InternalSwiftStaticMirror",
    "libFoundation",
    "libFoundationXML",
    "libFoundationEssentials",
    "libFoundationNetworking",
    "libFoundationInternationalization",
    "libicuuc",
    "libicudata",
    "libicuucswift",
    "libicui18nswift",
    "libicudataswift",
  ]

  static func computeContext(
    context: BundlerContext,
    command: BundleCommand,
    manifest: PackageManifest
  ) throws(Error) -> Context {
    // GenericLinuxBundler's additional context only exists to allow other
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

    log.info("Bundling '\(additionalContext.cosmeticBundleName ?? appBundleName)'")

    let structure = BundleStructure(
      at: root,
      forApp: context.appName,
      withIdentifier: context.appConfiguration.identifier
    )
    try structure.createDirectories()

    try createMetadataFiles(
      structure: structure,
      context: context,
      additionalContext: additionalContext
    )

    let executableArtifact = context.executableArtifact
    try copyExecutable(at: executableArtifact, to: structure.mainExecutable)

    try await copyDependencies(structure: structure, context: context)

    try copyResources(
      from: context.productsDirectory,
      to: structure.resources
    )

    try copyAppIconIfPresent(context, structure)

    return structure
  }

  // MARK: Private methods

  /// Creates the app's desktop file, and its DBus service file if the app has
  /// been configured as DBus activatable.
  private static func createMetadataFiles(
    structure: BundleStructure,
    context: BundlerContext,
    additionalContext: Context
  ) throws(Error) {
    // Create desktop file (and DBus service file if required)
    let relativeExecutablePath = structure.mainExecutable.path(
      relativeTo: structure.root
    )
    let executableLocation =
      additionalContext.installationRoot / relativeExecutablePath
    try createDesktopFile(
      at: structure.desktopFile,
      appName: context.appName,
      iconName: structure.icon1024x1024.deletingPathExtension().lastPathComponent,
      appConfiguration: context.appConfiguration,
      installedExecutableLocation: executableLocation
    )
    if context.appConfiguration.dbusActivatable {
      try createDBusServiceFile(
        at: structure.dbusServiceFile,
        appIdentifier: context.appConfiguration.identifier,
        installedExecutableLocation: executableLocation
      )
    }
  }

  private static func copyDependencies(
    structure: BundleStructure,
    context: BundlerContext
  ) async throws(Error) {
    // Copy all executable dependencies into the bundle next to the main
    // executable
    for (name, dependency) in context.builtDependencies {
      guard dependency.product.type == .executable else {
        continue
      }

      for artifact in dependency.artifacts {
        let source = artifact.location
        let destination = structure.bin / source.lastPathComponent
        do {
          try FileManager.default.copyItem(
            at: source,
            to: destination
          )
        } catch {
          let message = ErrorMessage.failedToCopyExecutableDependency(
            name: name,
            source: source,
            destination: destination
          )
          throw Error(message, cause: error)
        }
      }
    }
    
    try await copyDynamicLibraryDependencies(
      of: structure.mainExecutable,
      to: structure.lib,
      productsDirectory: context.productsDirectory
    )
  }

  /// Copies dynamic library dependencies of the specified executable file into
  /// a given destination directory, and updates the runpaths of the executable
  /// and moved dynamic
  /// libraries accordingly.
  ///
  /// For now this sticks to handling the Swift runtime libraries and dynamic
  /// libraries produced directly by the build, because there are many
  /// problematic dynamic libraries out there such as Gtk which break things
  /// when you try to distribute them.
  private static func copyDynamicLibraryDependencies(
    of appExecutable: URL,
    to destination: URL,
    productsDirectory: URL
  ) async throws(Error) {
    log.info("Copying dynamic libraries (and Swift runtime)")
    let allowedLibrariesDirectory = productsDirectory.actuallyResolvingSymlinksInPath()

    let output = try await Error.catch(withMessage: .failedToEnumerateDynamicDependencies) {
      try await Process.create(
        "ldd",
        arguments: [appExecutable.path],
        environment: [
          "LD_LIBRARY_PATH": allowedLibrariesDirectory.path
        ],
        runSilentlyWhenNotVerbose: false
      ).getOutput()
    }

    // Parse ldd output
    let libraries = output.split(separator: "\n")
      .compactMap { line in
        // Parse each line and simply ignore any we can't parse.
        try? lddLineParser.parse(line)
      }
      .map(URL.init(fileURLWithPath:))
      .filter { library in
        // Ensure that the library is on our allow list or was a product of
        // the built.
        let libraryName = String(library.lastPathComponent.split(separator: ".")[0])
        return dynamicLibraryBundlingAllowList.contains(libraryName)
          || library.actuallyResolvingSymlinksInPath().path.starts(
            with: allowedLibrariesDirectory.path
          )
      }

    for library in libraries {
      try await copyDynamicLibrary(library, toDirectory: destination)
    }

    // Update the main executable's runpath
    let relativeDestination = destination.path(
      relativeTo: appExecutable.deletingLastPathComponent()
    )
    do {
      try await PatchElfTool.setRunpath(
        of: appExecutable,
        to: "$ORIGIN/\(relativeDestination)"
      )
    } catch {
      throw Error(.failedToUpdateMainExecutableRunpath(executable: appExecutable), cause: error)
    }
  }

  /// Copies a dynamic library to the specified destination directory. Resolves
  /// symlinks to copy the actual library and not the symlink, but uses the
  /// provided file name for the destination file (not the resolved name).
  private static func copyDynamicLibrary(
    _ source: URL,
    toDirectory destinationDirectory: URL
  ) async throws(Error) {
    let destination = destinationDirectory.appendingPathComponent(
      source.lastPathComponent
    )

    // Resolve symlinks in case the library itself is a symlinnk (we want
    // to copy the actual library not the symlink).
    let resolvedSourceURL = source.actuallyResolvingSymlinksInPath()

    // Copy the library to the provided destination directory.
    do {
      try FileManager.default.copyItem(at: resolvedSourceURL, to: destination)
    } catch {
      throw Error(
        .failedToCopyDynamicLibrary(source: resolvedSourceURL, destination: destination),
        cause: error
      )
    }

    // Update the library's runpath so that it only looks for its dependencies in
    // the current directory (before falling back to the system wide default runpath).
    do {
      try await PatchElfTool.setRunpath(of: destination, to: "$ORIGIN")
    } catch {
      throw Error(
        .failedToCopyDynamicLibrary(source: resolvedSourceURL, destination: destination),
        cause: error
      )
    }
  }

  /// Copies the app's icon into the bundle if an icon was provided. Doesn't
  /// perform any resizing for now, but may in the future.
  private static func copyAppIconIfPresent(
    _ context: BundlerContext,
    _ structure: BundleStructure
  ) throws(Error) {
    guard let path = context.appConfiguration.icon else {
      return
    }

    let source = context.packageDirectory.appendingPathComponent(path)
    let destination = structure.icon1024x1024
    do {
      try FileManager.default.copyItem(at: source, to: destination)
    } catch {
      throw Error(.failedToCopyIcon(source: source, destination: destination), cause: error)
    }
  }

  /// Copies any resource bundles produced by the build system and changes
  /// their extension from `.resources` to `.bundle` for consistency with
  /// bundling on Apple platforms.
  private static func copyResources(
    from sourceDirectory: URL,
    to destinationDirectory: URL
  ) throws(Error) {
    let contents: [URL]
    do {
      contents = try FileManager.default.contentsOfDirectory(at: sourceDirectory)
    } catch {
      throw Error(.failedToEnumerateResourceBundles(directory: sourceDirectory), cause: error)
    }

    for bundle in contents {
      guard bundle.pathExtension == "resources" && bundle.exists(withType: .directory) else {
        continue
      }

      log.info("Copying resource bundle '\(bundle.lastPathComponent)'")

      let bundleName = bundle.deletingPathExtension().lastPathComponent
      let destinationBundle = destinationDirectory / "\(bundleName).bundle"

      do {
        try FileManager.default.copyItem(at: bundle, to: destinationBundle)
      } catch {
        throw Error(
          .failedToCopyResourceBundle(source: bundle, destination: destinationBundle),
          cause: error
        )
      }
    }
  }

  /// Copies the built executable into the app bundle.
  /// - Parameters:
  ///   - source: The location of the built executable.
  ///   - destination: The target location of the built executable (the file not the directory).
  private static func copyExecutable(
    at source: URL, to destination: URL
  ) throws(Error) {
    log.info("Copying executable")
    do {
      try FileManager.default.copyItem(at: source, to: destination)
    } catch {
      throw Error(.failedToCopyExecutable(source: source, destination: destination), cause: error)
    }
  }

  /// Creates an app's `.desktop` file.
  /// - Parameters:
  ///   - desktopFile: The desktop file to create.
  ///   - appName: The app's name.
  ///   - iconName: The name of the icon (the icon's file name without the
  ///     extension).
  ///   - appConfiguration: The app's configuration.
  ///   - installedExecutableLocation: The location the the executable will end
  ///     up at on disk once installed.
  private static func createDesktopFile(
    at desktopFile: URL,
    appName: String,
    iconName: String,
    appConfiguration: AppConfiguration.Flat,
    installedExecutableLocation: URL
  ) throws(Error) {
    log.info("Creating '\(desktopFile.lastPathComponent)'")

    let escapedExecPath = installedExecutableLocation.path
      .replacingOccurrences(of: " ", with: "\\ ")
    var properties = [
      ("Type", "Application"),
      ("Version", "1.0"),  // The version of the target desktop spec, not the app
      ("Name", appName),
      ("Comment", appConfiguration.appDescriptionOrDefault),
      ("Exec", "\(escapedExecPath) %U"),
      ("Icon", iconName),
      ("Terminal", "false"),
      ("Categories", ""),
    ]

    if appConfiguration.dbusActivatable {
      properties.append(("DBusActivatable", "true"))
    }

    if !appConfiguration.urlSchemes.isEmpty {
      properties.append(
        (
          "MimeType",
          appConfiguration.urlSchemes.map { scheme in
            "x-scheme-handler/\(scheme)"
          }.joined(separator: ";")
        )
      )
    }

    let contents = encodeIniSection(title: "Desktop Entry", properties: properties)
    let data = Data(contents.utf8)
    do {
      try data.write(to: desktopFile)
    } catch {
      throw Error(.failedToCreateDesktopFile(desktopFile), cause: error)
    }
  }

  /// Creates an app's `.service` file.
  /// - Parameters:
  ///   - dbusServiceFile: The DBus service file to create.
  ///   - appIdentifier: The app's identifier.
  ///   - installedExecutableLocation: The location the the executable will end
  ///     up at on disk once installed.
  private static func createDBusServiceFile(
    at dbusServiceFile: URL,
    appIdentifier: String,
    installedExecutableLocation: URL
  ) throws(Error) {
    let properties = [
      ("Name", appIdentifier),
      ("Exec", "\"\(installedExecutableLocation.path)\""),
    ]

    let contents = encodeIniSection(title: "D-BUS Service", properties: properties)
    let data = Data(contents.utf8)
    do {
      try data.write(to: dbusServiceFile)
    } catch {
      throw Error(.failedToCreateDBusServiceFile(dbusServiceFile), cause: error)
    }
  }

  private static func encodeIniSection(
    title: String,
    properties: [(String, String)]
  ) -> String {
    "[\(title)]\n" + properties.map { "\($0)=\($1)" }.joined(separator: "\n")
  }
}
