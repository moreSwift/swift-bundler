import ArgumentParser
import Foundation

/// The subcommand for booting Android emulators.
struct EmulatorsBootCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "boot",
    abstract: "Boot an Android emulator."
  )

  /// The name of the emulator to boot.
  @Argument(
    help: "The name of the emulator to start.")
  var name: String

  /// Arguments to pass through to the 'emulator' CLI.
  @Argument(
    parsing: .postTerminator,
    help: "Additional arguments for the 'emulator' CLI.")
  var emulatorArguments: [String] = []

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages.")
  public var verbose = false

  @Flag(
    name: .long,
    help: "Attach to 'emulator' CLI after booting the emulator.")
  var attach = false

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    try await RichError<SwiftBundlerError>.catch {
      log.info("Booting '\(name)'")
      try await AndroidVirtualDeviceManager.bootVirtualDevice(
        AndroidVirtualDevice(name: name),
        additionalArguments: emulatorArguments,
        detach: !attach
      )
    }
  }
}
