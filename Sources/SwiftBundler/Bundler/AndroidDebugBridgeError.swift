import Foundation
import ErrorKit

extension AndroidDebugBridge {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``AndroidDebugBridge``.
  enum ErrorMessage: Throwable {
    case failedToLocateADBExecutable(_ expectedLocation: URL?)
    case failedToCheckWhetherDeviceIsEmulator(_ identifier: String)
    case failedToGetEmulatorAVDName(_ identifier: String)
    case failedToParseEmulatorAVDNameOutput(_ output: String)

    var userFriendlyMessage: String {
      switch self {
        case .failedToLocateADBExecutable(let expectedLocation):
          var message = "Failed to locate 'adb' executable"
          if let expectedLocation {
            message += "; expected location was '\(expectedLocation.path)'"
          }
          return message
        case .failedToCheckWhetherDeviceIsEmulator(let identifier):
          return "Failed to check whether adb connected device '\(identifier)' is an emulator"
        case .failedToGetEmulatorAVDName(let identifier):
          return "Failed to get AVD name of adb connected emulator '\(identifier)'"
        case .failedToParseEmulatorAVDNameOutput(let output):
          return "Failed to parse emulator avd name from adb output:\n\(output)"
      }
    }
  }
}
