import ArgumentParser
import Foundation

/// The subcommand for listing available emulators.
struct EmulatorsListCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "list",
    abstract: "List available Android emulators."
  )

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages.")
  public var verbose = false

  @Flag(
    name: .customLong("booted"),
    help: "Only show booted emulators.")
  public var filterBooted = false

  @Flag(
    name: .customLong("not-booted"),
    help: "Only show emulators that aren't booted.")
  public var filterNotBooted = false

  func wrappedValidate() throws(RichError<SwiftBundlerError>) {
    if filterBooted && filterNotBooted {
      log.error("'--booted' and '--not-booted' cannot be used simultaneously")
      Foundation.exit(1)
    }
  }

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    let bootedEmulators = try await RichError<SwiftBundlerError>.catch {
      try await AndroidVirtualDeviceManager.enumerateBootedVirtualDevices()
    }
    var emulators: [AndroidVirtualDevice]
    if filterBooted {
      emulators = bootedEmulators
    } else {
      emulators = try await RichError<SwiftBundlerError>.catch {
        try await AndroidVirtualDeviceManager.enumerateVirtualDevices()
      }

      if filterNotBooted {
        emulators = emulators.filter { !bootedEmulators.contains($0) }
      }
    }

    Output {
      Section("Emulators") {
        if emulators.isEmpty {
          "No emulators found".italic
        } else {
          List {
            for emulator in emulators {
              if bootedEmulators.contains(emulator) {
                "\(emulator.name) (booted)"
              } else {
                emulator.name
              }
            }
          }
        }
      }
      Section("Booting an emulator") {
        ExampleCommand("swift bundler emulators boot [name]")
      }
    }.show()
  }
}
