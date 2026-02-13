import ArgumentParser
import Foundation

/// The subcommand for listing available devices.
struct DevicesListCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "list",
    abstract: "List available iOS, tvOS, visionOS and Android devices."
  )

  @Option(
    help: "A search term to filter devices with.")
  var filter: String?

  @Option(
    name: .customLong("os"),
    help: "Only show devices for a specific OS.",
    transform: { osString in
      guard let os = OS(rawValue: osString) else {
        throw SwiftBundlerError.invalidOS(osString)
      }

      return os
    })
  public var oses: [OS] = []

  @Flag(
    name: .customLong("apple"),
    help: "Only show Apple device simulators.")
  public var filterApple = false

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages.")
  public var verbose = false

  func wrappedValidate() throws(RichError<SwiftBundlerError>) {
    if filterApple && !oses.isEmpty {
      // This is a useless thing to do, so we make them explicitly mutually exclusive
      // in case gets themself into a confusing situation (e.g. where --filter-apple
      // and --os are both used in an existing command, and then they remove
      // --filter-apple expecting Android devices to show up)
      throw RichError(.commandLineValidationError(
        "'--filter-apple' and '--os' cannot be used together"
      ))
    }
  }

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    let oses: [OS]
    if filterApple {
      oses = OS.allCases.filter(\.isAppleOS)
    } else {
      oses = self.oses.isEmpty ? OS.allCases : self.oses
    }

    let devices = try await RichError<SwiftBundlerError>.catch {
      try await DeviceManager.listPhysicalConnectedDevices(
        oses: oses,
        searchTerm: filter
      )
    }

    Output {
      Section("Devices") {
        if devices.isEmpty {
          "None found".italic
        } else {
          KeyedList {
            for device in devices {
              // Devices with ids are exactly the non-host devices. All of the
              // devices enumerated by the above method will be non-host devices.
              if let id = device.id {
                KeyedList.Entry(id, device.describe(includingId: false))
              } else {
                log.warning(
                  """
                  Invariant failure: Encountered physical connected device \
                  '\(device.description)' without id (is it a host device?)
                  """
                )
              }
            }
          }
        }
      }
    }.show()
  }
}
