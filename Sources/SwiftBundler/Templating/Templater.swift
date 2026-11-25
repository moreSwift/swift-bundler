import Foundation
import TOMLKit
import Version

/// A utility for creating packages from package templates.
enum Templater {
  /// Create a basic project that just prints hello world when run.
  /// - Parameters:
  ///   - outputDirectory: The directory to create the project in.
  ///   - arguments: The arguments to the template.
  ///   - swiftToolchain: An alternative Swift toolchain to use.
  static func createSkeletonProject(
    in outputDirectory: URL,
    arguments: TemplateArguments,
    swiftToolchain: URL?
  ) async throws(Error) {
    do {
      try await Error.catch(withMessage: .failedToCreateBareMinimumPackage) {
        try await SwiftPackageManager.createPackage(
          in: outputDirectory,
          name: arguments.packageName,
          toolchain: swiftToolchain
        )
      }

      log.info("Updating indentation to '\(arguments.indentationStyle.defaultValueDescription)'")
      try updateIndentationStyle(in: outputDirectory, from: .spaces(4), to: arguments.indentationStyle)

      try createPackageConfigurationFile(
        in: outputDirectory,
        packageName: arguments.packageName,
        configuration: arguments.configuration
      )
    } catch {
      attemptCleanup(outputDirectory)
      throw error
    }
  }

  /// Creates a package from the specified template.
  /// - Parameters:
  ///   - outputDirectory: The directory to create the package in.
  ///   - template: The template to use to create the package.
  ///   - arguments: The arguments to the template.
  ///   - overlays: The optional template overlays to enable.
  ///   - forceCreation: If `true`, the package will be created even if the selected template doesn't support the user's system and Swift version.
  ///     will be added to the package (enabling ergonomic debugging with VSCode).
  ///   - swiftToolchain: An alternative Swift toolchain to use.
  static func createProject(
    in outputDirectory: URL,
    from template: Template,
    arguments: TemplateArguments,
    overlays: [TemplateConfiguration.OptionalOverlay.Name],
    forceCreation: Bool,
    swiftToolchain: URL?
  ) async throws(Error) {
    guard template.isPublic else {
      throw Error(.templateNotPublic(template))
    }

    guard !FileManager.default.fileExists(atPath: outputDirectory.path) else {
      throw Error(.packageDirectoryAlreadyExists(outputDirectory))
    }

    log.info("Creating package from the '\(template.name)' template")

    if !forceCreation {
      // Verify that this machine's Swift version is supported
      try await verifyTemplateIsSupported(
        template.name,
        template.configuration,
        swiftToolchain: swiftToolchain
      )
    }

    // Create the output directory
    do {
      try FileManager.default.createDirectory(at: outputDirectory)
    } catch {
      throw Error(.failedToCreateOutputDirectory(outputDirectory), cause: error)
    }

    // Apply the template
    do {
      try applyTemplate(
        template,
        to: outputDirectory,
        packageName: arguments.packageName,
        identifier: arguments.configuration.identifier,
        indentationStyle: arguments.indentationStyle
      )
    } catch {
      // Cleanup output directory
      attemptCleanup(outputDirectory)
      throw error
    }

    for overlayName in overlays {
      guard let overlay = template.configuration.optionalOverlays[overlayName] else {
        throw Error(.noSuchOverlay(overlayName))
      }
    }
    if arguments.addVSCodeOverlay {
      let vsCodeOverlay = template.repository.checkout / "VSCode"
      guard vsCodeOverlay.exists(withType: .directory) else {
        throw Error(.missingVSCodeOverlay)
      }

      do {
        try applyTemplate(
          vsCodeOverlay,
          to: outputDirectory,
          packageName: arguments.packageName,
          identifier: arguments.configuration.identifier,
          indentationStyle: arguments.indentationStyle
        )
      } catch {
        attemptCleanup(outputDirectory)
        throw error
      }
    }

    try createPackageConfigurationFile(
      in: outputDirectory,
      packageName: arguments.packageName,
      configuration: arguments.configuration
    )
  }

  static func createPackageConfigurationFile(
    in packageDirectory: URL,
    packageName: String,
    configuration: AppConfiguration
  ) throws(Error) {
    // Create package configuration file
    let file = PackageConfiguration.standardConfigurationFileLocation(
      for: packageDirectory
    )
    let configuration = PackageConfiguration(apps: [
      packageName: configuration
    ])

    try Error.catch {
      try PackageConfiguration.writeConfiguration(configuration, to: file)
    }
  }

  /// Verifies that the given template supports this machine's Swift version.
  /// - Parameters:
  ///   - name: The name of the template being checked.
  ///   - configuration: The configuration of the template to check.
  ///   - swiftToolchain: An alternative Swift toolchain to use.
  /// - Returns: An error if this machine's Swift version is not supported by the template.
  static func verifyTemplateIsSupported(
    _ name: Template.Name,
    _ configuration: TemplateConfiguration.Flat,
    swiftToolchain: URL?
  ) async throws(Error) {
    // Verify that the installed Swift version is supported
    let version = try await Error.catch {
      try await SwiftPackageManager.getSwiftVersion(toolchain: swiftToolchain)
    }

    if let minimumSwiftVersion = configuration.minimumSwiftVersion,
        version < minimumSwiftVersion
    {
      let message = ErrorMessage.templateDoesNotSupportInstalledSwiftVersion(
        template: name,
        version: version,
        minimumSupportedVersion: minimumSwiftVersion
      )
      throw Error(message)
    }
  }

  /// Applies a template to a directory (processes and copies the template's files).
  /// - Parameters:
  ///   - template: The template.
  ///   - outputDirectory: The directory to copy the resulting files to.
  ///   - packageName: The name of the package.
  ///   - identifier: The package's identifier (e.g. 'com.example.ExampleApp').
  ///   - indentationStyle: The style of indentation to use.
  /// - Returns: A failure if template application fails.
  static func applyTemplate(
    _ template: Template,
    to outputDirectory: URL,
    packageName: String,
    identifier: String,
    indentationStyle: IndentationStyle
  ) throws(Error) {
    if let base = template.configuration.base {
      let baseTemplate = try Error.catch {
        try template.repository.resolveTemplate(base)
      }

      try applyTemplate(
        baseTemplate,
        to: outputDirectory,
        packageName: packageName,
        identifier: identifier,
        indentationStyle: indentationStyle
      )
    }

    log.info("Applying '\(template.name)' template")

    guard
      let enumerator = FileManager.default.enumerator(
        at: template.location,
        includingPropertiesForKeys: nil
      )
    else {
      throw Error(.failedToEnumerateTemplateContents(template: template.name))
    }

    // Enumerate the template's files
    let excluded = Set(["Template.toml"])
    let files =
      enumerator
      .compactMap { $0 as? URL }
      .filter { !excluded.contains($0.lastPathComponent) }
      .filter { $0.exists(withType: .file) }

    // Process and copy each file
    for file in files {
      try processAndCopyFile(
        file,
        from: template.location,
        to: outputDirectory,
        packageName: packageName,
        identifier: identifier
      )
    }

    try updateIndentationStyle(in: outputDirectory, from: .tabs, to: indentationStyle)
  }

  /// Updates the indentation style of all files within the given folder with another indentation style.
  ///
  /// This function may break code it touches if the original indentation sequence (``IndentationStyle/string``) occurs in any non-indentation
  /// contexts. Therefore it is safest to use this function on directories whose original indentation style is ``IndentationStyle/tabs``.
  /// - Parameters:
  ///   - directory: The directory to update the indentation style in.
  ///   - indentationStyle: The new indentation style.
  static func updateIndentationStyle(
    in directory: URL,
    from originalStyle: IndentationStyle,
    to newStyle: IndentationStyle
  ) throws(Error) {
    guard originalStyle != newStyle else {
      return
    }

    guard
      let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: nil
      )
    else {
      throw Error(
        .failedToUpdateIndentationStyle(directory: directory),
        cause: ErrorMessage.failedToEnumerateOutputFiles
      )
    }

    do {
      for case let file as URL in enumerator {
        if file.exists(withType: .file) {
          var contents = try String(contentsOf: file)
          contents = contents.replacingOccurrences(of: originalStyle.string, with: newStyle.string)
          try contents.write(to: file, atomically: false, encoding: .utf8)
        }
      }
    } catch {
      throw RichError(.failedToUpdateIndentationStyle(directory: directory), cause: error)
    }
  }

  // MARK: Private methods

  /// Attempts to delete the output directory after a failed attempt to create a package.
  /// - Parameter outputDirectory: The output directory to remove.
  private static func attemptCleanup(_ outputDirectory: URL) {
    try? FileManager.default.removeItem(at: outputDirectory)
  }

  /// Processes a template file (replacing occurences of `{{variable}}` with the variable's values) and then copies it to a destination directory.
  ///
  /// Currently only the `PACKAGE` and `IDENTIFIER` variables are available.
  /// - Parameters:
  ///   - file: The template file.
  ///   - templateDirectory: The directory of the template that the file is from.
  ///   - outputDirectory: The directory to output the file to (the file gets copied to the same relative location as in `templateDirectory`).
  ///   - packageName: The name of the package.
  ///   - identifier: The package's identifier (e.g. 'com.example.ExampleApp').
  /// - Returns: A failure if file processing or copying fails.
  private static func processAndCopyFile(
    _ file: URL,
    from templateDirectory: URL,
    to outputDirectory: URL,
    packageName: String,
    identifier: String
  ) throws(Error) {
    let variables: [String: String] = [
      "PACKAGE": packageName,
      "IDENTIFIER": identifier,
    ]

    // Read the file's contents
    var contents: String
    do {
      contents = try String(contentsOf: file)
    } catch {
      let template = templateDirectory.lastPathComponent
      throw Error(
        .failedToReadFile(template: template, file: file),
        cause: error
      )
    }

    // If the file is a template, replace all instances of `{{variable}}` with the variable's value
    var file = file
    if file.pathExtension == "template" {
      for (variable, value) in variables {
        contents = contents.replacingOccurrences(of: "{{\(variable)}}", with: value)
      }
      file = file.deletingPathExtension()
    }

    // Get the file's relative path (compared to the template root directory)
    var relativePath = file.path(relativeTo: templateDirectory)

    // Compute the output directory, replacing occurrences of `{{variable}}` in the original path with the variable's value
    for (variable, value) in variables {
      relativePath = relativePath.replacingOccurrences(of: "{{\(variable)}}", with: value)
    }

    // Write to the output file
    let outputFile = outputDirectory.appendingPathComponent(relativePath)
    try? FileManager.default.createDirectory(at: outputFile.deletingLastPathComponent())

    do {
      try contents.write(to: outputFile)
    } catch {
      throw Error(.failedToWriteToOutputFile(file: file), cause: error)
    }
  }
}
