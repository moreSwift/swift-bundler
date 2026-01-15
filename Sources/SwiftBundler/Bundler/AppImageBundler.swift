import Foundation
import Parsing

/// The bundler for creating Linux AppImages.
enum AppImageBundler: Bundler {
  typealias Context = Void

  static let outputIsRunnable = true
  static let requiresBuildAsDylib = false

  /// Computes the location of the desktop file created in the given context.
  static func desktopFileLocation(for context: BundlerContext) -> URL {
    context.outputDirectory.appendingPathComponent(
      GenericLinuxBundler.BundleStructure
        .desktopFileName(for: context.appName)
    )
  }

  static func intendedOutput(
    in context: BundlerContext,
    _ additionalContext: Void
  ) -> BundlerOutputStructure {
    let bundle = context.outputDirectory
      .appendingPathComponent("\(context.appName).AppImage")
    return BundlerOutputStructure(
      bundle: bundle,
      executable: bundle,
      additionalOutputs: [
        desktopFileLocation(for: context)
      ]
    )
  }

  static func bundle(
    _ context: BundlerContext,
    _ additionalContext: Context
  ) async throws(Error) -> BundlerOutputStructure {
    let outputStructure = intendedOutput(in: context, additionalContext)
    let bundleName = outputStructure.bundle.lastPathComponent

    // Run generic bundler
    let structure: GenericLinuxBundler.BundleStructure = try await Error.catch {
      try await GenericLinuxBundler.bundle(
        context,
        GenericLinuxBundler.Context(cosmeticBundleName: bundleName)
      )
    }

    try createSymlinks(in: structure)

    // Copy the app's desktop file to the root of the output directory for
    // convenience.
    try FileManager.default.copyItem(
      at: structure.desktopFile,
      to: desktopFileLocation(for: context),
      errorMessage: ErrorMessage.failedToCopyDesktopFile
    )

    // This isn't strictly necessary but it's probably a nice courtesy to
    // anyone poking around in the outputs of this bundler if we let them
    // know that the directory in question is meant to be an `AppDir`.
    let appDir = context.outputDirectory / "\(context.appName).AppDir"
    try FileManager.default.moveItem(
      at: structure.root,
      to: appDir,
      errorMessage: ErrorMessage.failedToRenameGenericBundle
    )

    log.info("Converting '\(context.appName).AppDir' to '\(bundleName)'")
    try await Error.catch(withMessage: .failedToBundleAppDir) {
      try await AppImageTool.bundle(appDir: appDir, to: outputStructure.bundle)
    }

    return outputStructure
  }

  // MARK: Private methods

  /// Creates the symlinks required to turn a generic bundle into an `AppDir`.
  private static func createSymlinks(
    in structure: GenericLinuxBundler.BundleStructure
  ) throws(Error) {
    // Create `.DirIcon` and `[AppName].png` if an icon is present. Both are
    // just symlinks to the real icon file at `iconRelativePath`.
    let icon = structure.icon1024x1024
    if icon.exists() {
      let relativeIconPath = icon.path(relativeTo: structure.root)
      try FileManager.default.createSymlink(
        at: structure.root / icon.lastPathComponent,
        withRelativeDestination: relativeIconPath,
        errorMessage: ErrorMessage.failedToCreateSymlink
      )

      try FileManager.default.createSymlink(
        at: structure.root / ".DirIcon",
        withRelativeDestination: icon.lastPathComponent,
        errorMessage: ErrorMessage.failedToCreateSymlink
      )
    }

    // Create `AppRun` symlink pointing to the main executable.
    try FileManager.default.createSymlink(
      at: structure.root / "AppRun",
      withRelativeDestination: structure.mainExecutable.path(relativeTo: structure.root),
      errorMessage: ErrorMessage.failedToCreateSymlink
    )

    // Create symlink in root pointing to desktop file.
    try FileManager.default.createSymlink(
      at: structure.root / structure.desktopFile.lastPathComponent,
      withRelativeDestination: structure.desktopFile.path(relativeTo: structure.root),
      errorMessage: ErrorMessage.failedToCreateSymlink
    )
  }
}
