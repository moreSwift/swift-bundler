import Foundation

/// A utility for creating an ICNS from `.icon` files.
enum LayeredIconCompiler {
  /// Creates an `AppIcon.icns` in the given directory from the given `.icon` file.
  ///
  /// iOS is NOT supported.
  /// - Parameters:
  ///   - icon: The input icon. Must be a `.icon` file. An error is returned
  ///     if the icon's path extension is not `icon` (case insensitive).
  ///   - outputFile: The location of the output `icns` file.
  ///   - platform: The platform the icon is being created for.
  ///   - version: The platform version the icon is being created for.
  /// - Returns: A dictionary representation of the generated PartialInfo.plist.
  static func createIcon(
    from icon: URL,
    outputFile: URL,
    forPlatform platform: Platform,
    withPlatformVersion version: String
  ) async throws(Error) -> [String: Any] {
    guard icon.pathExtension.lowercased() == "icon" else {
      throw Error(.notAnIconFile(icon))
    }

    let temporaryDirectory = FileManager.default.temporaryDirectory
    let workPath = temporaryDirectory.appendingPathComponent("BundlerWork-\(UUID().uuidString)")

    try FileManager.default.createDirectory(
      at: workPath,
      errorMessage: ErrorMessage.failedToCreateIconDirectory
    )

    let temporaryIcon = workPath.appendingPathComponent("AppIcon.icon")
    try Error.catch(withMessage: .failedToCopyFile(icon, temporaryIcon)) {
      try FileManager.default.copyItem(at: icon, to: temporaryIcon)
    }

    let partialInfoPlistPath = workPath.appendingPathComponent("PartialInfo.plist")
    let targetDeviceArguments =
      platform
      .asApplePlatform?
      .actoolTargetDeviceNames
      .flatMap { ["--target-device", $0] } ?? []
    let process = Process.create(
      "/usr/bin/xcrun",
      arguments: [
        "actool",
        "--compile", workPath.path,
        "--enable-on-demand-resources", "NO",
        "--app-icon", "AppIcon",
        "--platform", platform.sdkName,
        "--include-all-app-icons",
        "--minimum-deployment-target", version,
        "--output-partial-info-plist", partialInfoPlistPath.path,
      ] + targetDeviceArguments + [temporaryIcon.path]
    )
    do {
      try await process.runAndWait()
    } catch {
      // Remove the work directory before throwing.
      try? FileManager.default.removeItem(at: workPath)
      throw Error(.failedToCompileIcon, cause: error)
    }

    if !partialInfoPlistPath.exists(withType: .file) {
      try? FileManager.default.removeItem(at: workPath)
      throw Error(.failedToCompileIcon)
    }

    let plistData: Data
    do {
      plistData = try Data(contentsOf: partialInfoPlistPath)
    } catch {
      try? FileManager.default.removeItem(at: workPath)
      throw Error(.failedToCompileIcon, cause: error)
    }

    var plist: [String: Any]? = nil
    do {
      plist =
        try PropertyListSerialization.propertyList(
          from: plistData,
          options: [],
          format: nil
        ) as? [String: Any]
    } catch {
      try? FileManager.default.removeItem(at: workPath)
      throw Error(.failedToDecodePartialInfoPlist(partialInfoPlistPath), cause: error)
    }

    guard let plist else {
      try? FileManager.default.removeItem(at: workPath)
      throw Error(.failedToDecodePartialInfoPlist(partialInfoPlistPath))
    }

    if platform == .macOS || platform == .macCatalyst {
      let generatedIcns = workPath.appendingPathComponent("AppIcon.icns")

      guard generatedIcns.exists(withType: .file) else {
        try? FileManager.default.removeItem(at: workPath)
        throw Error(.failedToCompileICNS)
      }

      do {
        try FileManager.default.moveItem(at: generatedIcns, to: outputFile)
      } catch {
        try? FileManager.default.removeItem(at: workPath)
        throw Error(.failedToCopyFile(generatedIcns, outputFile), cause: error)
      }

      try FileManager.default.removeItem(
        at: workPath,
        errorMessage: ErrorMessage.failedToRemoveIconDirectory
      )
      return plist
    } else {
      let fileEnumerator = FileManager.default.enumerator(
        at: workPath, includingPropertiesForKeys: nil)
      let pngFiles =
        fileEnumerator?.allObjects.compactMap { $0 as? URL }
        .filter { $0.pathExtension.lowercased() == "png" } ?? []

      // Move all PNG files to the output directory
      for pngFile in pngFiles {
        let destination =
          outputFile
          .deletingLastPathComponent()
          .appendingPathComponent(pngFile.lastPathComponent)
        do {
          try FileManager.default.moveItem(at: pngFile, to: destination)
        } catch {
          try? FileManager.default.removeItem(at: workPath)
          throw Error(.failedToCopyFile(pngFile, destination), cause: error)
        }
      }
      try FileManager.default.removeItem(
        at: workPath,
        errorMessage: ErrorMessage.failedToRemoveIconDirectory
      )
    }

    return plist
  }
}
