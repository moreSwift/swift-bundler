import Crypto
import Foundation
import XMLCoder
import ErrorKit

/// The bundler for creating Windows MSI installers. The output of this bundler
/// isn't directly executable.
enum MSIBundler: Bundler {
  typealias Context = Void

  static let outputIsRunnable = false

  static func intendedOutput(
    in context: BundlerContext,
    _ additionalContext: Void
  ) -> BundlerOutputStructure {
    return BundlerOutputStructure(
      bundle: context.outputDirectory / "\(context.appName).msi",
      executable: nil,
      additionalOutputs: []
    )
  }

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

  static func bundle(
    _ context: BundlerContext,
    _ additionalContext: Void
  ) async throws(Error) -> BundlerOutputStructure {
    let outputStructure = intendedOutput(in: context, additionalContext)

    let wxsFile = context.outputDirectory / "project.wxs"
    let genericBundlerOutput: GenericWindowsBundler.BundleStructure = try await Error.catch {
      try await GenericWindowsBundler.bundle(
        context,
        GenericWindowsBundler.Context()
      )
    }

    let contents = try generateWXSFileContents(
      genericBundle: genericBundlerOutput,
      appName: context.appName,
      appConfiguration: context.appConfiguration,
      context: context
    )

    try Error.catch(withMessage: .failedToWriteWXSFile) {
      try contents.write(to: wxsFile)
    }

    log.info("Running WiX MSI builder")
    let process = Process.create(
      "wix",
      arguments: [
        "build",
        "-b", genericBundlerOutput.root.path,
        "-o", outputStructure.bundle.path,
        "-arch", "x64",
        wxsFile.path,
      ],
      runSilentlyWhenNotVerbose: false
    )

    try await Error.catch(withMessage: .failedToRunWiX) {
      try await process.runAndWait()
    }

    if let codeSigningContext = context.windowsCodeSigningContext {
      log.info("Signing installer")
      try await Error.catch {
        try await WindowsCodeSigner.signFile(
          outputStructure.bundle,
          context: codeSigningContext
        )
      }
    }

    return outputStructure
  }

  static func generateWXSFileContents(
    genericBundle: GenericWindowsBundler.BundleStructure,
    appName: String,
    appConfiguration: AppConfiguration.Flat,
    context: BundlerContext
  ) throws(Error) -> Data {
    let file = try generateWXSFile(
      genericBundle: genericBundle,
      appName: appName,
      appConfiguration: appConfiguration,
      context: context
    )

    let encoder = XMLEncoder()
    encoder.outputFormatting = [.prettyPrinted]

    return try Error.catch(withMessage: .failedToSerializeWXSFile) {
      try encoder.encode(
        file,
        withRootKey: "Wix",
        header: XMLHeader(version: 1, encoding: "UTF-8")
      )
    }
  }

  static func generateWXSFile(
    genericBundle: GenericWindowsBundler.BundleStructure,
    appName: String,
    appConfiguration: AppConfiguration.Flat,
    context: BundlerContext
  ) throws(Error) -> WXSFile {
    // TODO: Allow manufacturer to be configured
    // For now drop the last segment of the app's bundle identifier.
    let manufacturer = appConfiguration.identifier.split(separator: ".")
      .dropLast().joined(separator: ".")

    // Assume that the bundle identifier will stay the same for any given app.
    // This feels like a reasonable requirement for app to get stable upgrade
    // codes.
    let upgradeCode = appConfiguration.upgradeCode ?? GUID.random(
      withSeed: appConfiguration.identifier
    ).description

    let installFolder = try enumerate(
      genericBundle.root,
      excluding: [genericBundle.mainExecutable],
      id: "InstallFolder"
    )

    let mainExecutablePath = genericBundle.mainExecutable.path(
      relativeTo: genericBundle.root
    )

    let icons: [WXSFile.Icon]
    let iconProperties: [WXSFile.Property]
    if let iconPath = appConfiguration.icon {
      let id = "icon.ico"
      let icoFile = try Error.catch {
        try GenericWindowsBundler.prepareIcon(
          iconPath: iconPath,
          context: context,
          // The output directory gets cleared between builds, and the icon
          // is prepared by the prepareAdditionalSPMBuildArguments phase. We
          // only have to prepare the icon here if that phase didn't already
          // produce an ico file.
          skipIfPresent: true
        )
      }
      icons = [WXSFile.Icon(id: id, sourceFile: icoFile.path)]
      iconProperties = [WXSFile.Property(id: "ARPPRODUCTICON", value: id)]
    } else {
      icons = []
      iconProperties = []
    }

    let package = WXSFile.Package(
      language: .english,
      manufacturer: manufacturer,
      name: appName,
      upgradeCode: upgradeCode,
      version: appConfiguration.version,
      majorUpgrade: WXSFile.MajorUpgrade(
        allowSameVersionUpgrades: .yes,
        downgradeErrorMessage:
          "A later version of [ProductName] is already installed. Setup will now exit"
      ),
      mediaTemplate: WXSFile.MediaTemplate(embedCab: .yes),
      icons: icons,
      properties: [
        // Was running into issues where the installer would remove an old version
        // of a file but wouldn't install the new version, found this solution
        // at https://stackoverflow.com/a/32607186
        WXSFile.Property(id: "REINSTALLMODE", value: "amus"),
      ] + iconProperties,
      standardDirectories: [
        WXSFile.StandardDirectory(
          id: "ProgramFiles64Folder",
          directories: [installFolder.renamed(to: appName)]
        ),
        WXSFile.StandardDirectory(
          id: "ProgramMenuFolder",
          directories: [
            WXSFile.Directory(id: "AppShortcutFolder", name: appName)
          ]
        ),
      ],
      componentGroups: [
        WXSFile.ComponentGroup(
          id: "Components",
          directory: "InstallFolder",
          components: [
            WXSFile.Component(
              id: "MainExecutable",
              files: [
                WXSFile.File(
                  id: "MainExecutable",
                  source: mainExecutablePath
                )
              ]
            ),
            WXSFile.Component(
              id: "ShortcutComponent",
              shortcuts: [
                WXSFile.Shortcut(
                  id: "ApplicationStartMenuShortcut",
                  directory: "AppShortcutFolder",
                  advertise: .no,
                  name: appName,
                  description: "Launch \(appName)",
                  target: "[#MainExecutable]",
                  workingDirectory: "InstallFolder"
                ),
                WXSFile.Shortcut(
                  id: "UninstallShortcut",
                  directory: "AppShortcutFolder",
                  advertise: .no,
                  name: "\(appName) uninstall",
                  description: "Uninstalls \(appName)",
                  target: "[System64Folder]msiexec.exe",
                  arguments: "/x [ProductCode]"
                ),
              ],
              folderRemovals: [
                WXSFile.RemoveFolder(id: "InstallFolder", on: "uninstall"),
                WXSFile.RemoveFolder(
                  id: "AppShortcutFolder",
                  directory: "AppShortcutFolder",
                  on: "uninstall"
                ),
              ],
              registryValues: [
                WXSFile.RegistryValue(
                  root: "HKCU",
                  key: "Software\\Microsoft\\\(appConfiguration.identifier)",
                  name: "installed",
                  type: "integer",
                  value: "1",
                  keyPath: .yes
                )
              ]
            ),
          ]
        )
      ],
      additionalChildren: appConfiguration.msi?.wxsExtras ?? []
    )

    return WXSFile(
      xmlns: "http://wixtoolset.org/schemas/v4/wxs",
      package: package
    )
  }

  /// Enumerates a directory to produce a WXS directory description.
  /// - Parameters:
  ///   - directory: The directory to enumerate.
  ///   - root: The root directory that all paths should be relative to.
  ///     Defaults to `directory`.
  ///   - id: The WXS id to give the directory.
  private static func enumerate(
    _ directory: URL,
    withRespectTo root: URL? = nil,
    excluding excludedItems: [URL] = [],
    id: String? = nil
  ) throws(Error) -> WXSFile.Directory {
    let root = root ?? directory
    let excludedPaths = excludedItems.map(\.path)

    let items: [URL] = try Error.catch(withMessage: .failedToEnumerateBundle) {
      try FileManager.default.contentsOfDirectory(at: directory)
    }.filter { item in
      // For some reason URL comparison seems to be a little broken on Windows.
      // URLs with identical paths get evaluated as distinct URLs, so we have to
      // convert to paths before comparison.
      return !excludedPaths.contains(item.path)
    }

    let files = items.filter { item in
      item.exists(withType: .file)
    }.map { file in
      let source = file.path(relativeTo: root)
      return WXSFile.File(source: source)
    }

    let directories = try items.filter { item in
      item.exists(withType: .directory)
    }.map { (subdirectory) throws(Error) -> WXSFile.Directory in
      try enumerate(subdirectory, withRespectTo: root, excluding: excludedItems)
    }

    // Enumerate each directory and then combine files and directories into
    // a description of the current directory.
    return WXSFile.Directory(
      id: id,
      name: directory.lastPathComponent,
      directories: directories,
      files: files
    )
  }
}
