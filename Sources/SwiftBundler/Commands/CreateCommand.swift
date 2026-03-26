import ArgumentParser
import Foundation
import Version

/// The subcommand for creating new app packages from templates.
struct CreateCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "create",
    abstract: "Create a new app package."
  )

  /// The app's name. Must only contain characters from the English alphabet.
  @Argument(
    help: "The app's name. Must only contain characters from the English alphabet.")
  var appName: String

  /// The app's identifier. Should use reverse domain name notation.
  @Option(
    name: .shortAndLong,
    help: "The app's identifier. (e.g. 'com.example.ExampleApp')")
  var identifier: String?

  /// The app's initial version.
  @Option(
    name: .long,
    help: "The app's initial version.")
  var version: String?

  /// The app's category.
  @Option(
    name: .long,
    help: "The app's category.")
  var category: String?

  /// The app's icon file (1024x1024 png or icns file).
  @Option(
    name: [.customLong("icon")],
    help: "The app's icon file (1024x1024 png or icns file).",
    transform: URL.init(fileURLWithPath:))
  var iconFile: URL?

  /// An Info.plist file containing entries to add to the app's configuration.
  @Option(
    name: [.customLong("info-plist")],
    help: "An Info.plist file containing entries to add to the app's configuration.",
    transform: URL.init(fileURLWithPath:))
  var infoPlistFile: URL?

  /// A custom directory to create the app in. Default: create a new directory at './[app-name]'.
  @Option(
    name: [.customShort("d"), .customLong("directory")],
    help: "Directory to create the app in. Default: create a new directory at './[app-name]'.",
    transform: URL.init(fileURLWithPath:))
  var packageDirectory: URL?

  /// Template to create the app from.
  @Option(
    name: [.customShort("t"), .customLong("template")],
    help: "Template to create the app from.")
  var templateName: String?

  /// A directory to search for the template in.
  @Option(
    name: .long,
    help: "A directory to search for the template in.",
    transform: URL.init(fileURLWithPath:))
  var templateRepository: URL?

  /// An alternative Swift toolchain to use.
  @Option(
    help: "An alternative Swift toolchain to use",
    transform: URL.init(fileURLWithPath:))
  var toolchain: URL?

  /// The indentation style to create the package with.
  @Option(
    name: .long,
    help: "Custom indentation style: either 'tabs' or 'spaces=[count]'.")
  var indentation: IndentationStyle = .spaces(4)

  /// If `true`, force creation of the package even if the template does not support the current OS and installed Swift version.
  @Flag(
    name: .shortAndLong,
    help:
      "Force creation even if the template does not support the current OS and installed Swift version."
  )
  var force = false

  @Flag(
    name: .customLong("vscode"),
    help: "Add vscode configuration files necessary to enable ergonomic debugging.")
  var addVSCodeOverlay = false

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages.")
  public var verbose = false

  func wrappedValidate() throws(RichError<SwiftBundlerError>) {
    guard Self.isValidAppName(appName) else {
      let message = """
        Invalid app name, app names must only include uppercase and lowercase \
        characters from the English alphabet
        """
      throw RichError(cause: ValidationError(message))
    }

    if templateName == nil && templateRepository != nil {
      let message = """
        The '--template-repository' option can only be used with the \
        '--template' option
        """
      throw RichError(cause: ValidationError(message))
    }
  }

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    let defaultPackageDirectory = URL(fileURLWithPath: ".").appendingPathComponent(appName)
    let packageDirectory = packageDirectory ?? defaultPackageDirectory

    let configuration = try RichError<SwiftBundlerError>.catch {
      try AppConfiguration.create(
        appName: appName,
        version: version,
        identifier: identifier,
        category: category,
        infoPlistFile: infoPlistFile,
        iconFile: iconFile
      )
    }

    var template: Template?
    let elapsed = try await Stopwatch.time { () async throws(RichError<SwiftBundlerError>) in
      // Create package from template
      if let templateRepository = templateRepository, let templateName = templateName {
        template = try await RichError<SwiftBundlerError>.catch {
          try await Templater.createPackage(
            in: packageDirectory,
            from: templateName,
            in: templateRepository,
            packageName: appName,
            configuration: configuration,
            forceCreation: force,
            indentationStyle: indentation,
            addVSCodeOverlay: addVSCodeOverlay,
            swiftToolchain: toolchain
          )
        }
      } else {
        template = try await RichError<SwiftBundlerError>.catch {
          try await Templater.createPackage(
            in: packageDirectory,
            from: templateName,
            packageName: appName,
            configuration: configuration,
            forceCreation: force,
            indentationStyle: indentation,
            addVSCodeOverlay: addVSCodeOverlay,
            swiftToolchain: toolchain
          )
        }
      }

      if let iconFile = iconFile {
        let outputIcon = packageDirectory.appendingPathComponent(iconFile.lastPathComponent)
        do {
          try FileManager.default.copyItem(at: iconFile, to: outputIcon)
        } catch {
          throw RichError(
            .failedToCopyIcon(source: iconFile, destination: outputIcon),
            cause: error
          )
        }
      }
    }

    log.info(
      "Done in \(elapsed.secondsString). Package located at '\(packageDirectory.relativePath)'")

    Self.printNextSteps(packageDirectory: packageDirectory, template: template)
  }

  /// Prints a helpful message telling the user what to try next. Also notifies them of any required system dependencies.
  /// - Parameters:
  ///   - packageDirectory: The package's root directory.
  ///   - template: The template that the package was created from.
  static func printNextSteps(packageDirectory: URL, template: Template?) {
    Output {
      if let template = template, let dependencies = template.manifest.systemDependencies {
        ""
        Section("System dependencies") {
          "The '\(template.name)' template requires the following system dependencies to be installed:"
          ""
          KeyedList {
            for (key, value) in dependencies {
              KeyedList.Entry(key) {
                Line {
                  if let packages = value.brew {
                    "Can be installed via '"
                    ExampleCommand("brew install \(packages)", withPrompt: false)
                    "'"
                  } else {
                    "Must be manually installed"
                  }
                }
              }
            }
          }
        }
      } else {
        ""
      }
      Section("Getting started") {
        ExampleCommand("cd \(packageDirectory.relativePath.quotedIfNecessary)")
        ExampleCommand("swift bundler run")
      }
    }.show()

    if template == nil {
      Output {
        "warning".yellow.bold
          + ": You have created a project without a template and it will not have a UI framework set up out of the box. Did you mean to use a template?"
        ""
        ExampleCommand("swift bundler templates list")
        ExampleCommand("swift bundler create [app-name] --template [template]")
        ""
      }.show()
    }
  }

  /// App names can only contain characters from the English alphabet (to avoid things getting a bit complex when figuring out the product name).
  /// - Parameter name: The name to verify.
  /// - Returns: Whether the app name is valid or not.
  static func isValidAppName(_ name: String) -> Bool {
    let allowedCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    let characters = Set(name)

    return characters.subtracting(allowedCharacters).isEmpty
  }
}
