import ErrorKit

extension DeviceManager {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``DeviceManager``.
  enum ErrorMessage: Throwable {
    case deviceNotFound(specifier: String, platform: Platform?)

    var userFriendlyMessage: String {
      switch self {
        case .deviceNotFound(let specifier, .none):
          return Output {
            """
            Device not found for device specifier '\(specifier)'. If you're \
            expecting an iOS device, ensure it's plugged in and turned on. If \
            you're expecting a tvOS device, open Xcode, navigate to Window > \
            Devices and Simulators, and ensure that the device has been paired. \
            If the device has not been paired, open Settings on the TV and \
            navigate to Remotes and Devices > Remote App and Devices, and it \
            should appear in Xcode's Devices and Simulators window with an \
            option to pair it.

            """

            Section("List available devices", trailingNewline: false) {
              ExampleCommand("swift bundler devices list")
            }
          }.description
        case .deviceNotFound(let specifier, .some(let platform)):
          return Output {
            switch platform {
              case .tvOS:
                """
                Device specifier '\(specifier)' doesn't match any paired tvOS \
                devices. To pair a tvOS device, open Settings on the TV and \
                navigate to Remotes and Devices > Remote App and Devices, then \
                open Xcode on your host machine and navigate to Window > Devices \
                and Simulators. Xcode should discover the device and give you \
                the option to pair it.
                """
              case .iOS:
                """
                Device specifier '\(specifier)' doesn't match any connected or \
                paired iOS devices. Ensure the target device is connected and \
                turned on, or if you are expecting to use a Wi-Fi connected \
                device ensure that you've used it with this laptop previously. \
                Xcode's Devices and Simulators window can be used to pair devices.
                """
              default:
                """
                Device not found for device specifier '\(specifier)' with platform \
                '\(platform)'.
                """
            }

            ""

            Section("List available devices", trailingNewline: false) {
              ExampleCommand("swift bundler devices list")
            }
          }.description
      }
    }
  }
}
