import ArgumentParser
import Foundation

/// The subcommand for listing available devices.
struct DevicesListCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "list",
    abstract: "List available iOS, tvOS and visionOS devices."
  )

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages.")
  public var verbose = false

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    let devices = try await RichError<SwiftBundlerError>.catch {
      try await DeviceManager.listDestinations()
        .filter { device in
          !device.platform.isSimulator
        }
        .compactMap { device -> ConnectedAppleDevice? in
          switch device {
            case .host, .macCatalyst, .connectedAndroidDevice:
              return nil
            case .connectedAppleDevice(let device):
              return device
          }
        }
    }

    Output {
      Section("Devices") {
        KeyedList {
          for device in devices {
            KeyedList.Entry(device.id, "\(device.name) (\(device.status))")
          }
        }
      }
    }.show()
  }
}
