import Foundation

/// A utility for creating Xcode related support files (i.e. Xcode schemes).
enum XcodeSupportGenerator {
  /// Generates the schemes required for Xcode to build and run a package.
  /// - Parameters:
  ///   - configuration: The package's configuration.
  ///   - packageDirectory: The package's root directory.
  static func generateXcodeSupport(
    for configuration: PackageConfiguration,
    in packageDirectory: URL
  ) throws(Error) {
    let schemesDirectory = try getSchemesDirectory(in: packageDirectory)
    for (app, appConfiguration) in configuration.apps ?? [:] {
      try generateAppScheme(for: app, with: appConfiguration, in: schemesDirectory)
    }
  }

  /// Gets the location to create Xcode schemes for a given package.
  /// - Parameter packageDirectory: The root directory of the package.
  /// - Returns: The package's schemes directory.
  private static func getSchemesDirectory(
    in packageDirectory: URL
  ) throws(Error) -> URL {
    let schemesDirectory =
      packageDirectory / ".swiftpm/xcode/xcshareddata/xcschemes"

    do {
      try FileManager.default.createDirectory(at: schemesDirectory)
    } catch {
      throw Error(.failedToCreateSchemesDirectory(schemesDirectory), cause: error)
    }

    return schemesDirectory
  }

  /// Generates the Xcode schemes for an app.
  /// - Parameters:
  ///   - app: The name of the app.
  ///   - configuration: The app's configuration.
  ///   - schemesDirectory: The directory to output the schemes to.
  private static func generateAppScheme(
    for app: String,
    with configuration: AppConfiguration,
    in schemesDirectory: URL
  ) throws(Error) {
    let contents = try generateAppSchemeContents(for: app, with: configuration)
    do {
      try contents.write(to: schemesDirectory / "\(app).xcscheme")
    } catch {
      throw Error(.failedToWriteToAppScheme(app: app), cause: error)
    }
  }

  /// Generates the contents of the Xcode scheme for an app.
  /// - Parameters:
  ///   - app: The name of the app.
  ///   - configuration: The app's configuration.
  /// - Returns: The contents of the scheme.
  private static func generateAppSchemeContents(
    for app: String,
    with configuration: AppConfiguration
  ) throws(Error) -> String {
    log.info("Generating scheme for '\(app).app'")

    let product = configuration.product

    // Get the global output directory
    let outputDirectory = try Error.catch {
      let applicationSupport = try System.getApplicationSupportDirectory()

      // This shouldn't be able to happen, but it would break stuff if it did
      guard !applicationSupport.path.contains("'") else {
        throw Error(.applicationSupportDirectoryCannotContainSingleQuote(applicationSupport))
      }

      return applicationSupport / "build"
    }

    // Get the output app bundle location
    let outputAppBundle = outputDirectory.appendingPathComponent("\(product).app")
    do {
      try FileManager.default.createDirectory(at: outputAppBundle)
    } catch {
      throw Error(.failedToCreateOutputBundle, cause: error)
    }

    // The escaped strings required to fill in the template
    let escapedOutputPath = outputDirectory.path
      .replacingOccurrences(of: "'", with: "'\"'\"'")
    let escapedOutputBundlePath = outputAppBundle.path
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    let packagePath = "${WORKSPACE_PATH}/../../../"

    // Commands to put in the scheme
    let fixPath =
      "export PATH=`zsh --login -c '[ -f /etc/zshrc ] && . /etc/zshrc; [ -f ~/.zshrc ] && . ~/.zshrc; echo $PATH'`"
    let command = "swift-bundler bundle"
    let arguments =
      "\(app) -d \(packagePath) --products-directory ${BUILT_PRODUCTS_DIR} -o '\(escapedOutputPath)' --skip-build --built-with-xcode --platform ${TARGET_DEVICE_PLATFORM_NAME:-$PLATFORM_NAME}"
    let createBundle = "\(fixPath); \(command) \(arguments)"
      .replacingOccurrences(of: "&", with: "&amp;")

    // Create the scheme's contents from a massive template
    return """
      <?xml version="1.0" encoding="UTF-8"?>
      <Scheme
         LastUpgradeVersion = "1300"
         version = "1.7">
         <BuildAction
            parallelizeBuildables = "YES"
            buildImplicitDependencies = "YES">
            <PostActions>
               <ExecutionAction
                  ActionType = "Xcode.IDEStandardExecutionActionsCore.ExecutionActionType.ShellScriptAction">
                  <ActionContent
                     title = "Bundle executable"
                     scriptText = "\(createBundle)">
                     <EnvironmentBuildable>
                        <BuildableReference
                           BuildableIdentifier = "primary"
                           BlueprintIdentifier = "\(product)"
                           BuildableName = "\(product)"
                           BlueprintName = "\(product)"
                           ReferencedContainer = "container:">
                        </BuildableReference>
                     </EnvironmentBuildable>
                  </ActionContent>
               </ExecutionAction>
            </PostActions>
            <BuildActionEntries>
               <BuildActionEntry
                  buildForTesting = "YES"
                  buildForRunning = "YES"
                  buildForProfiling = "YES"
                  buildForArchiving = "NO"
                  buildForAnalyzing = "YES">
                  <BuildableReference
                     BuildableIdentifier = "primary"
                     BlueprintIdentifier = "\(product)"
                     BuildableName = "\(product)"
                     BlueprintName = "\(product)"
                     ReferencedContainer = "container:">
                  </BuildableReference>
               </BuildActionEntry>
            </BuildActionEntries>
         </BuildAction>
         <TestAction
            buildConfiguration = "Debug"
            selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
            selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
            shouldUseLaunchSchemeArgsEnv = "YES">
            <Testables>
            </Testables>
         </TestAction>
         <LaunchAction
            buildConfiguration = "Debug"
            selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
            selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
            launchStyle = "0"
            useCustomWorkingDirectory = "NO"
            ignoresPersistentStateOnLaunch = "NO"
            debugDocumentVersioning = "YES"
            debugServiceExtension = "internal"
            allowLocationSimulation = "YES">
            <PathRunnable
               runnableDebuggingMode = "0"
               FilePath = "\(escapedOutputBundlePath)">
            </PathRunnable>
            <MacroExpansion>
               <BuildableReference
                  BuildableIdentifier = "primary"
                  BlueprintIdentifier = "\(product)"
                  BuildableName = "\(product)"
                  BlueprintName = "\(product)"
                  ReferencedContainer = "container:">
               </BuildableReference>
            </MacroExpansion>
         </LaunchAction>
         <ProfileAction
            buildConfiguration = "Release"
            shouldUseLaunchSchemeArgsEnv = "YES"
            savedToolIdentifier = ""
            useCustomWorkingDirectory = "NO"
            debugDocumentVersioning = "YES">
            <BuildableProductRunnable
               runnableDebuggingMode = "0">
               <BuildableReference
                  BuildableIdentifier = "primary"
                  BlueprintIdentifier = "\(product)"
                  BuildableName = "\(product)"
                  BlueprintName = "\(product)"
                  ReferencedContainer = "container:">
               </BuildableReference>
            </BuildableProductRunnable>
         </ProfileAction>
         <AnalyzeAction
            buildConfiguration = "Debug">
         </AnalyzeAction>
         <ArchiveAction
            buildConfiguration = "Release"
            revealArchiveInOrganizer = "YES">
         </ArchiveAction>
      </Scheme>
      """
  }
}
