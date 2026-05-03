import ArgumentParser
import Foundation
import TOMLKit

/// The command for converting xcodeprojs to Swift Bundler projects.
struct ConvertCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "convert",
    abstract: "Convert an xcodeproj to a Swift Bundler project."
  )

  @Argument(
    help: "Xcodeproj to convert.",
    transform: URL.init(fileURLWithPath:)
  )
  var xcodeFile: URL

  @Option(
    name: [.customShort("o"), .customLong("out")],
    help: "The output directory.",
    transform: URL.init(fileURLWithPath:)
  )
  var outputDirectory: URL

  @Flag(
    name: [.customLong("dont-warn")],
    help: "Disables the experimental feature warning"
  )
  var dontWarn = false

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages."
  )
  public var verbose = false

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    // - [x] Convert executable targets
    // - [x] Convert library dependency targets
    // - [x] Preserve project structure
    // - [x] Extract version and identifier
    // - [ ] Extract code signing settings
    // - [x] Extract platform deployment versions
    // - [ ] Extract asset catalog compiler settings
    // - [ ] Extract indentation settings
    // - [ ] Handle tests

    #if !SUPPORT_XCODEPROJ
      // Throw an error as early as possible if the host platform isn't supported
      throw RichError<SwiftBundlerError>(
        cause: XcodeprojConverter.ErrorMessage.hostPlatformNotSupported
      )
    #else
      if !dontWarn {
        log.warning(
          "Converting xcodeprojs is currently an experimental feature. Proceed with caution."
        )
        print("[press ENTER to continue]", terminator: "")
        _ = readLine()
      }

      switch xcodeFile.pathExtension {
        case "xcodeproj":
          try await RichError<SwiftBundlerError>.catch {
            try await XcodeprojConverter.convertProject(
              xcodeFile,
              outputDirectory: outputDirectory
            )
          }
        case "xcworkspace":
          try await RichError<SwiftBundlerError>.catch {
            try await XcodeprojConverter.convertWorkspace(
              xcodeFile,
              outputDirectory: outputDirectory
            )
          }
        default:
          log.error(
            """
            Unknown file extension '\(xcodeFile.pathExtension)'. Expected \
            'xcodeproj' or 'xcworkspace'
            """
          )
          Foundation.exit(1)
      }
    #endif
  }
}
