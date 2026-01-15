import Foundation
import Parsing

/// The bundler for creating Linux RPM packages. The output of this bundler
/// isn't executable.
enum RPMBundler: Bundler {
  typealias Context = Void

  static let outputIsRunnable = false
  static let requiresBuildAsDylib = false

  static func intendedOutput(
    in context: BundlerContext,
    _ additionalContext: Void
  ) -> BundlerOutputStructure {
    let bundle = context.outputDirectory
      .appendingPathComponent("\(context.appName).rpm")
    return BundlerOutputStructure(
      bundle: bundle,
      executable: nil,
      additionalOutputs: []
    )
  }

  static func bundle(
    _ context: BundlerContext,
    _ additionalContext: Context
  ) async throws(Error) -> BundlerOutputStructure {
    let outputStructure = intendedOutput(in: context, additionalContext)
    let bundleName = outputStructure.bundle.lastPathComponent

    let escapedAppName = context.appName.replacingOccurrences(of: " ", with: "-").lowercased()
    let appVersion = context.appConfiguration.version
    let rpmBuildDirectory = RPMBuildDirectory(
      at: context.outputDirectory / "rpmbuild",
      escapedAppName: escapedAppName,
      appVersion: appVersion
    )

    // The 'source' directory for our RPM. Doesn't actual contain source code
    // cause it's all pre-compiled.
    let sourceDirectory = context.outputDirectory / "\(escapedAppName)-\(appVersion)"

    // Run the generic bundler
    let installationRoot = URL(fileURLWithPath: "/opt/\(escapedAppName)")
    let structure: GenericLinuxBundler.BundleStructure = try await Error.catch {
      try await GenericLinuxBundler.bundle(
        context,
        GenericLinuxBundler.Context(
          cosmeticBundleName: bundleName,
          installationRoot: installationRoot
        )
      )
    }

    // Create the an `rpmbuild` directory with the structure required by the
    // rpmbuild tool.
    try rpmBuildDirectory.createDirectories()

    // Copy `.generic` bundle to give it the name we want it to have inside
    // the .tar.gz archive.
    do {
      try FileManager.default.copyItem(at: structure.root, to: sourceDirectory)
    } catch {
      throw Error(
        .failedToCopyGenericBundle(source: structure.root, destination: sourceDirectory),
        cause: error
      )
    }

    // Generate an archive of the source directory. Again, it's not actually
    // the source code of the app, but it is according to RPM terminology.
    log.info("Archiving bundle")
    try await Error.catch {
      try await ArchiveTool.createTarGz(
        of: sourceDirectory,
        at: rpmBuildDirectory.appSourceArchive
      )
    }

    // Generate the RPM spec for our 'build' process (no actual building
    // happens in our rpmbuild step, only copying and system setup such as
    // installing desktop files).
    log.info("Creating RPM spec file")
    let specContents = generateSpec(
      escapedAppName: escapedAppName,
      appIdentifier: context.appConfiguration.identifier,
      appVersion: appVersion,
      appDescription: context.appConfiguration.appDescriptionOrDefault,
      appLicense: context.appConfiguration.licenseOrDefault,
      bundleStructure: structure,
      sourceArchiveName: rpmBuildDirectory.appSourceArchive.lastPathComponent,
      installationRoot: installationRoot,
      requirements: context.appConfiguration.rpmRequirements
    )

    do {
      try specContents.write(to: rpmBuildDirectory.appSpec)
    } catch {
      throw Error(.failedToWriteSpecFile(rpmBuildDirectory.appSpec), cause: error)
    }

    // Build the actual RPM.
    log.info("Running rpmbuild")
    let command = "rpmbuild"
    let arguments = [
      "--define", "_topdir \(rpmBuildDirectory.root.path)",
      "-v", "-bb", rpmBuildDirectory.appSpec.path,
    ]

    do {
      try await Process.create(command, arguments: arguments).runAndWait()
    } catch {
      throw Error(.failedToRunRPMBuildTool(command), cause: error)
    }

    // Find the produced RPM because rpmbuild doesn't really tell us where
    // it'll end up.
    guard let enumerator = FileManager.default.enumerator(
      at: rpmBuildDirectory.rpms,
      includingPropertiesForKeys: nil
    ) else {
      throw Error(.failedToEnumerateRPMs(rpmBuildDirectory.rpms))
    }

    guard
      let rpmFile = enumerator.compactMap({ file in
        file as? URL
      }).filter({ file in
        file.pathExtension == "rpm"
      }).first
    else {
      throw Error(.failedToFindProducedRPM(rpmBuildDirectory.rpms))
    }

    // Copy the rpm file to the previously declared output location
    try FileManager.default.copyItem(
      at: rpmFile,
      to: outputStructure.bundle,
      errorMessage: ErrorMessage.failedToCopyRPMToOutputDirectory
    )

    return outputStructure
  }

  /// Generates an RPM spec for the given application.
  static func generateSpec(
    escapedAppName: String,
    appIdentifier: String,
    appVersion: String,
    appDescription: String,
    appLicense: String,
    bundleStructure: GenericLinuxBundler.BundleStructure,
    sourceArchiveName: String,
    installationRoot: URL,
    requirements: [String]
  ) -> String {
    let relativeDesktopFileLocation = bundleStructure.desktopFile.path(
      relativeTo: bundleStructure.root
    )

    let relativeDBusServiceFileLocation = bundleStructure.dbusServiceFile.path(
      relativeTo: bundleStructure.root
    )

    // We install this as a 512x512 icon (even though it's 1024x1024)
    // because Linux doesn't seem to check for 1024x1024 icons, and it also
    // doesn't seem to care if the icon's size is incorrect. Will fix
    // eventually when revamping icon support.
    let relativeIconFileLocation = bundleStructure.icon1024x1024.path(
      relativeTo: bundleStructure.root
    )

    func copyToBuildRoot(_ relativePath: String) -> String {
      let quotedPath = shellQuoted(relativePath)
      return """
        FILE_SRC=$INSTALL_ROOT/\(quotedPath)
        FILE_DEST=$RPM_BUILD_ROOT/\(quotedPath)
        mkdir -p $(dirname "$FILE_DEST")
        cp "$FILE_SRC" "$FILE_DEST"
        """
    }

    let hasDBusService = bundleStructure.dbusServiceFile.exists()
    let installDBusServiceCommand =
      if hasDBusService {
        copyToBuildRoot(relativeDBusServiceFileLocation)
      } else {
        "# No desktop service file present"
      }

    let hasIcon = bundleStructure.icon1024x1024.exists()
    let installIconCommand =
      if hasIcon {
        copyToBuildRoot(relativeIconFileLocation)
      } else {
        "# No icon file present"
      }

    return """
      Name:           \(escapedAppName)
      Version:        \(appVersion)
      Release:        1%{?dist}
      Summary:        \(appDescription)

      License:        \(appLicense)
      Source0:        \(sourceArchiveName)

      \(requirements.map { "Requires:       \($0)" }.joined(separator: "\n"))

      %global debug_package %{nil}

      # Prevents rpmbuild from messing with our ELF files (since Swift Bundler
      # adds trailer data that gets stripped away when patching ELFs)
      %global _enable_debug_package 0
      %global __os_install_post /usr/lib/rpm/brp-compress %{nil}

      %description
      \(appDescription)

      %prep
      %setup

      %build

      %install
      INSTALL_ROOT=$RPM_BUILD_ROOT\(shellQuoted(installationRoot.path))

      rm -rf "$RPM_BUILD_ROOT"
      mkdir -p "$INSTALL_ROOT"
      cp -R * "$INSTALL_ROOT"

      \(copyToBuildRoot(relativeDesktopFileLocation))
      \(installDBusServiceCommand)
      \(installIconCommand)

      %post
      xdg-desktop-menu forceupdate
      xdg-icon-resource forceupdate

      %clean
      rm -rf "$RPM_BUILD_ROOT"

      %files
      \(rpmEscapedFilePath(installationRoot.path))
      \(rpmEscapedFilePath("/" + relativeDesktopFileLocation))
      \(hasDBusService ? rpmEscapedFilePath("/" + relativeDBusServiceFileLocation) : "")
      \(hasIcon ? rpmEscapedFilePath("/" + relativeIconFileLocation) : "")
      """
  }

  // TODO: I'm pretty sure this is wrong (leaving it for now cause I'm busy with
  //   something else and single quotes in directory names should be relatively rare)
  private static func shellQuoted(_ string: String) -> String {
    "'\(string.replacingOccurrences(of: "'", with: "\\'"))'"
  }

  private static func rpmEscapedFilePath(_ string: String) -> String {
    let value =
      string
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "%", with: "%%")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(value)\""
  }

  /// Checks a requirement name intended to be passed to an rpmspec `Requires:`
  /// field.
  static func isValidRequirement(_ name: String) -> Bool {
    // TODO: Find out what the actual naming restrictions are, these are just the ones
    //   we rely on/assume. RPM seems a bit cagey about the actual restrictions.
    name.allSatisfy { character in
      character.isASCII
        && !character.isWhitespace
        && !character.isNewline
        && character != ","
    }
  }
}
