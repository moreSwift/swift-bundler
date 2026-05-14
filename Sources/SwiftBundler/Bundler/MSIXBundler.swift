import Foundation
import ImageFormats

/// A bundler that creates MSIX packages.
enum MSIXBundler: Bundler {
  typealias Context = Void

  static let outputIsRunnable = true
  static let requiresBuildAsDylib = false

  static func prepareAdditionalSPMBuildArguments(
    _ context: BundlerContext,
    _ additionalContext: Context,
    dryRun: Bool
  ) async throws(Error) -> [String] {
    try await Error.catch {
      try await GenericWindowsBundler.prepareAdditionalSPMBuildArguments(
        context,
        GenericWindowsBundler.Context(),
        dryRun: dryRun
      )
    }
  }

  /// Prepares a 300x300 PNG icon.
  /// - Parameters:
  ///   - iconPath: The path to the source icon file relative to the package
  ///     root. If `nil`, a blank transparent icon will be generated.
  ///   - context: The bundler context.
  ///   - outputURL: The URL to write the prepared icon to.
  /// - Throws: An error if the icon could not be loaded, processed, or written.
  static func prepareMSIXIcon(
    iconPath: String?,
    context: BundlerContext,
    outputURL: URL
  ) throws(Error) {
    let image: Image<RGBA>
    if let iconPath {
      let icon = context.packageDirectory / iconPath
      image = try Error.catch(withMessage: .failedToLoadIcon(icon)) {
        let imageData = try Data(contentsOf: icon)
        return try Image<RGBA>.load(from: Array(imageData))
      }
    } else {
      image = Image<RGBA>(
        width: 300,
        height: 300,
        pixels: Array(repeating: RGBA(0, 0, 0, 0), count: 300 * 300)
      )
    }

    let scaledImage = image.linearlyDownscale(toWidth: 300, height: 300)

    let pngData = try Error.catch(withMessage: .failedToEncodePNG) {
      try scaledImage.encodeToPNG()
    }

    try Error.catch {
      try Data(pngData).write(to: outputURL)
    }
  }

  /// Creates the Assets directory in the bundle and returns its URL.
  /// - Parameter folderURL: The URL of the folder to create the Assets
  ///   directory in.
  /// - Throws: An error if the directory could not be created.
  /// - Returns: The URL of the created Assets directory.
  static func createAssetsDirectory(
    in folderURL: URL,
  ) throws(Error) -> URL {
    let assetsDirectory = folderURL / "Assets"
    try FileManager.default.createDirectory(
      at: assetsDirectory,
      errorMessage: ErrorMessage.failedToCreateAssetsDirectory
    )
    return assetsDirectory
  }

  static func bundle(
    _ context: BundlerContext,
    _ additionalContext: Void
  ) async throws(RichError<ErrorMessage>) -> BundlerOutputStructure {
    guard context.appConfiguration.msix != nil else {
      throw Error(.msixConfigurationRequired)
    }

    let genericBundlerOutput: GenericWindowsBundler.BundleStructure = try await Error.catch {
      try await GenericWindowsBundler.bundle(
        context,
        GenericWindowsBundler.Context()
      )
    }

    let stagingStructure = stagingStructure(for: context)
    try FileManager.default.moveItem(
      at: genericBundlerOutput.root,
      to: stagingStructure.root,
      errorMessage: ErrorMessage.failedToRenameGenericBundle
    )

    let assetsURL = try createAssetsDirectory(in: stagingStructure.root)
    let manifestURL = stagingStructure.root / "AppxManifest.xml"
    let iconURL = assetsURL / "AppIcon.png"

    log.info("Preparing icon for MSIX package")
    try prepareMSIXIcon(
      iconPath: context.appConfiguration.icon,
      context: context,
      outputURL: iconURL
    )

    log.info("Creating AppxManifest.xml")
    let relativeIconPath = iconURL.path(
      relativeTo: stagingStructure.root,
      withPathSeparator: "\\",
      includingRelativePathPrefix: false
    )
    let relativeExecutablePath = stagingStructure.mainExecutable.path(
      relativeTo: stagingStructure.root,
      withPathSeparator: "\\",
      includingRelativePathPrefix: false
    )
    try Error.catch {
      try AppxManifestCreator.createManifest(
        for: context,
        withIcons: AppxManifestCreator.IconPaths(
          square150x150: relativeIconPath,
          square44x44: relativeIconPath
        ),
        executablePath: relativeExecutablePath,
        outputURL: manifestURL
      )
    }

    return stagingStructure.asOutputStructure
  }

  static func intendedOutput(
    in context: BundlerContext,
    _ additionalContext: Void
  ) -> BundlerOutputStructure {
    return stagingStructure(for: context).asOutputStructure
  }

  private static func stagingStructure(
    for context: BundlerContext
  ) -> GenericWindowsBundler.BundleStructure {
    GenericWindowsBundler.BundleStructure(
      at: context.outputDirectory / "\(context.appName).msixStaging",
      forApp: context.appName,
      withIdentifier: context.appConfiguration.identifier
    )
  }
}
