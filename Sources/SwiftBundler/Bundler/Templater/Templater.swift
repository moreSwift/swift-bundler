import Foundation
import TOMLKit
import Version

/// A utility for creating packages from package templates.
enum Templater {
  /// The repository of default templates.
  static let defaultTemplateRepository = "https://github.com/moreSwift/swift-bundler-templates"

  /// Creates a package using an optionally specified template from the default
  /// template repository.
  ///
  /// Downloads the default template repository if it hasn't already been downloaded.
  /// - Parameters:
  ///   - outputDirectory: The directory to create the package in.
  ///   - template: The template to use to create the package.
  ///   - packageName: The name of the package.
  ///   - configuration: The app's configuration.
  ///   - forceCreation: If `true`, the package will be created even if the
  ///     selected template doesn't support the user's system and Swift version.
  ///   - indentationStyle: The indentation style to use.
  ///   - addVSCodeOverlay: If `true`, the VSCode overlay (containing
  ///     `launch.json` and `.vscode/tasks.json`), will be added to the package
  ///     (enabling ergonomic debugging with VSCode).
  ///   - swiftToolchain: An alternative Swift toolchain to use.
  /// - Returns: The template that the package was created from (or nil if none
  ///   were used), or a failure if package creation failed.
  static func createPackage(
    in outputDirectory: URL,
    from template: String?,
    packageName: String,
    configuration: AppConfiguration,
    forceCreation: Bool,
    indentationStyle: IndentationStyle,
    addVSCodeOverlay: Bool,
    swiftToolchain: URL?
  ) async throws(Error) -> Template? {
    if FileManager.default.fileExists(atPath: outputDirectory.path) {
      throw RichError(.packageDirectoryAlreadyExists(outputDirectory))
    }

    // If no template is specified, create the most basic package that just
    // prints 'Hello, World!'
    guard let template = template else {
      log.info("Creating package")

      do {
        do {
          try await SwiftPackageManager.createPackage(
            in: outputDirectory,
            name: packageName,
            toolchain: swiftToolchain
          )
        } catch {
          throw Error(.failedToCreateBareMinimumPackage, cause: error)
        }

        log.info("Updating indentation to '\(indentationStyle.defaultValueDescription)'")
        try updateIndentationStyle(in: outputDirectory, from: .spaces(4), to: indentationStyle)

        try createPackageConfigurationFile(
          in: outputDirectory,
          packageName: packageName,
          configuration: configuration
        )
      } catch {
        attemptCleanup(outputDirectory)
        // TODO: Figure out why Swift doesn't infer this thrown type. Perhaps we
        //   need full typed throws?
        // swiftlint:disable:next force_cast
        throw error as! Error
      }

      return nil
    }

    // If a template was specified: Get the default templates directory (and download if not present), and then create the package
    let templatesDirectory = try await getDefaultTemplatesDirectory(downloadIfNecessary: true)

    return try await createPackage(
      in: outputDirectory,
      from: template,
      in: templatesDirectory,
      packageName: packageName,
      configuration: configuration,
      forceCreation: forceCreation,
      indentationStyle: indentationStyle,
      addVSCodeOverlay: addVSCodeOverlay,
      swiftToolchain: swiftToolchain
    )
  }

  /// Creates a package from the specified template from the specified template repository.
  /// - Parameters:
  ///   - outputDirectory: The directory to create the package in.
  ///   - template: The template to use to create the package.
  ///   - templatesDirectory: The directory containing the template to use.
  ///   - packageName: The name of the package.
  ///   - configuration: The package's configuration.
  ///   - forceCreation: If `true`, the package will be created even if the selected template doesn't support the user's system and Swift version.
  ///   - indentationStyle: The indentation style to use.
  ///   - addVSCodeOverlay: If `true`, the VSCode overlay (containing `launch.json` and `.vscode/tasks.json`),
  ///     will be added to the package (enabling ergonomic debugging with VSCode).
  ///   - swiftToolchain: An alternative Swift toolchain to use.
  /// - Returns: The template that the package was created from, or a failure if package creation failed.
  static func createPackage(
    in outputDirectory: URL,
    from template: String,
    in templatesDirectory: URL,
    packageName: String,
    configuration: AppConfiguration,
    forceCreation: Bool,
    indentationStyle: IndentationStyle,
    addVSCodeOverlay: Bool,
    swiftToolchain: URL?
  ) async throws(Error) -> Template {
    if FileManager.default.fileExists(atPath: outputDirectory.path) {
      throw Error(.packageDirectoryAlreadyExists(outputDirectory))
    }

    // The `Base` template should not be used to create packages directly
    guard template != "Base" else {
      throw Error(.cannotCreatePackageFromBaseTemplate)
    }

    log.info("Creating package from the '\(template)' template")

    // Check that the template exists
    let templateDirectory = templatesDirectory.appendingPathComponent(template)
    guard templateDirectory.exists(withType: .directory) else {
      throw Error(.noSuchTemplate(template))
    }

    // Load the template manifest
    let manifestFile = templateDirectory.appendingPathComponent("Template.toml")
    let manifest = try TemplateManifest.load(from: manifestFile, template: template)

    if !forceCreation {
      // Verify that this machine's Swift version is supported
      try await verifyTemplateIsSupported(template, manifest, swiftToolchain: swiftToolchain)
    }

    // Create the output directory
    do {
      try FileManager.default.createDirectory(at: outputDirectory)
    } catch {
      throw Error(.failedToCreateOutputDirectory(outputDirectory), cause: error)
    }

    // Apply the base template first if it exists
    let baseTemplate = templatesDirectory.appendingPathComponent("Base")
    if baseTemplate.exists(withType: .directory) {
      // Set the indentation style to tab for now to avoid updating the tab
      // style twice because the final `applyTemplate` call will update all
      // files in the output directory
      do {
        try applyTemplate(
          baseTemplate,
          to: outputDirectory,
          packageName: packageName,
          identifier: configuration.identifier,
          indentationStyle: indentationStyle
        )
      } catch {
        attemptCleanup(outputDirectory)
        throw error
      }
    }

    if addVSCodeOverlay {
      let vsCodeOverlay = templatesDirectory.appendingPathComponent("VSCode")
      guard vsCodeOverlay.exists(withType: .directory) else {
        throw Error(.missingVSCodeOverlay)
      }

      do {
        try applyTemplate(
          vsCodeOverlay,
          to: outputDirectory,
          packageName: packageName,
          identifier: configuration.identifier,
          indentationStyle: indentationStyle
        )
      } catch {
        attemptCleanup(outputDirectory)
        throw error
      }
    }

    // Apply the template
    do {
      try applyTemplate(
        templateDirectory,
        to: outputDirectory,
        packageName: packageName,
        identifier: configuration.identifier,
        indentationStyle: indentationStyle
      )
    } catch {
      // Cleanup output directory
      attemptCleanup(outputDirectory)
      throw error
    }

    try createPackageConfigurationFile(
      in: outputDirectory,
      packageName: packageName,
      configuration: configuration
    )

    return Template(name: template, manifest: manifest)
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

  /// Gets the template with the given name in the given template repository. If
  /// no template repository is specified, the default template repository is
  /// used. If the default template repository hasn't been downloaded, it gets
  /// downloaded.
  static func template(
    named name: String,
    in templateRepository: URL?
  ) async throws(Error) -> Template {
    let templates = try await Error.catch {
      let templateRepository = if let templateRepository {
        templateRepository
      } else {
        try await Templater.getDefaultTemplatesDirectory(downloadIfNecessary: true)
      }
      return try Templater.enumerateTemplates(in: templateRepository)
    }

    let matchingTemplates = templates.filter { $0.name == name }
    guard let template = matchingTemplates.first else {
      throw RichError(.noSuchTemplate(name))
    }

    if matchingTemplates.count > 1 {
      log.warning("Multiple templates have name '\(name)'. Using first.")
    }

    return template
  }

  /// Verifies that the given template supports this machine's Swift version.
  /// - Parameters:
  ///   - name: The name of the template being checked.
  ///   - manifest: The manifest of the template to check.
  ///   - swiftToolchain: An alternative Swift toolchain to use.
  /// - Returns: An error if this machine's Swift version is not supported by the template.
  static func verifyTemplateIsSupported(
    _ name: String,
    _ manifest: TemplateManifest,
    swiftToolchain: URL?
  ) async throws(Error) {
    // Verify that the installed Swift version is supported
    let version = try await Error.catch {
      try await SwiftPackageManager.getSwiftVersion(toolchain: swiftToolchain)
    }

    if version < manifest.minimumSwiftVersion {
      let message = ErrorMessage.templateDoesNotSupportInstalledSwiftVersion(
        template: name,
        version: version,
        minimumSupportedVersion: manifest.minimumSwiftVersion
      )
      throw Error(message)
    }
  }

  /// Gets the default templates directory.
  /// - Parameter downloadIfNecessary: If `true` the default templates
  ///   repository is downloaded if the templates directory doesn't exist.
  /// - Returns: The default templates directory, or a failure if the templates
  ///   directory doesn't exist and couldn't be downloaded.
  static func getDefaultTemplatesDirectory(
    downloadIfNecessary: Bool
  ) async throws(Error) -> URL {
    // Get the templates directory
    let templatesDirectory = try Error.catch {
      try System.getApplicationSupportDirectory() / "templates"
    }

    // Download the templates if they don't exist
    if !templatesDirectory.exists(withType: .directory) {
      try await downloadDefaultTemplates(into: templatesDirectory)
    }

    return templatesDirectory
  }

  /// Updates the default templates to the latest version from GitHub.
  /// - Returns: A failure if updating fails.
  static func updateTemplates() async throws(Error) {
    let templatesDirectory = try await getDefaultTemplatesDirectory(downloadIfNecessary: false)

    guard templatesDirectory.exists(withType: .directory) else {
      try await downloadDefaultTemplates(into: templatesDirectory)
      return
    }

    do {
      try await Process.create(
        "git",
        arguments: [
          "fetch"
        ],
        directory: templatesDirectory
      ).runAndWait()

      try await Process.create(
        "git",
        arguments: [
          "checkout", "v\(SwiftBundler.version.major)",
        ],
        directory: templatesDirectory
      ).runAndWait()

      try await Process.create(
        "git",
        arguments: ["pull"],
        directory: templatesDirectory
      ).runAndWait()
    } catch {
      throw Error(.failedToPullLatestTemplates, cause: error)
    }
  }

  /// Gets the list of available templates from a templates directory.
  /// - Parameter templatesDirectory: The directory to search for templates in.
  /// - Returns: The available templates.
  static func enumerateTemplates(in templatesDirectory: URL) throws(Error) -> [Template] {
    do {
      let contents = try FileManager.default.contentsOfDirectory(
        at: templatesDirectory,
        includingPropertiesForKeys: nil,
        options: []
      )
      var templates: [Template] = []

      // Enumerate templates
      for directory in contents {
        guard directory.exists(withType: .directory) else {
          continue
        }

        let templateName = directory.lastPathComponent

        // Skip `Base` template, `VSCode` template, and `.git` directory
        guard
          templateName != "Base" && templateName != "VSCode" && !templateName.starts(with: ".")
        else {
          continue
        }

        // Load the template manifest file
        let manifestFile = directory.appendingPathComponent("Template.toml")
        let manifest = try TemplateManifest.load(from: manifestFile, template: templateName)

        let template = Template(name: templateName, manifest: manifest)
        templates.append(template)
      }

      return templates
    } catch {
      throw Error(.failedToEnumerateTemplates, cause: error)
    }
  }

  /// Downloads the default template repository.
  /// - Parameter directory: The directory to clone the template repository in.
  /// - Returns: A failure if cloning the repository fails.
  static func downloadDefaultTemplates(into directory: URL) async throws(Error) {
    log.info("Downloading default templates (\(defaultTemplateRepository))")

    // Remove the directory if it already exists
    if directory.exists() {
      try Error.catch {
        try FileManager.default.removeItem(at: directory)
      }
    }

    // Clone the templates repository
    let process = Process.create(
      "git",
      arguments: [
        "clone", "-b", "v\(SwiftBundler.version.major)",
        "\(defaultTemplateRepository)",
        directory.path,
      ]
    )

    do {
      try await process.runAndWait()
    } catch {
      throw Error(.failedToCloneTemplateRepository, cause: error)
    }
  }

  /// Applies a template to a directory (processes and copies the template's files).
  /// - Parameters:
  ///   - templateDirectory: The template's directory.
  ///   - outputDirectory: The directory to copy the resulting files to.
  ///   - packageName: The name of the package.
  ///   - identifier: The package's identifier (e.g. 'com.example.ExampleApp').
  ///   - indentationStyle: The style of indentation to use.
  /// - Returns: A failure if template application fails.
  static func applyTemplate(
    _ templateDirectory: URL,
    to outputDirectory: URL,
    packageName: String,
    identifier: String,
    indentationStyle: IndentationStyle
  ) throws(Error) {
    log.info("Applying '\(templateDirectory.lastPathComponent)' template")

    guard
      let enumerator = FileManager.default.enumerator(
        at: templateDirectory, includingPropertiesForKeys: nil)
    else {
      let template = templateDirectory.lastPathComponent
      throw Error(.failedToEnumerateTemplateContents(template: template))
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
        from: templateDirectory,
        to: outputDirectory,
        packageName: packageName,
        identifier: identifier
      )
    }

    if templateDirectory.lastPathComponent != "Base" {
      log.info("Updating indentation to '\(indentationStyle.defaultValueDescription)'")
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
