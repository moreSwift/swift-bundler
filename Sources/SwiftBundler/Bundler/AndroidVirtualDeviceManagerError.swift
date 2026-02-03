import Foundation
import ErrorKit

extension AndroidVirtualDeviceManager {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``AndroidVirtualDeviceManager``.
  enum ErrorMessage: Throwable {
    case failedToLocateAVDManagerExecutable(_ expectedLocation: URL?)
    case failedToLocateEmulatorCommandExecutable(_ expectedLocation: URL?)
    case cannotAttachToAlreadyBootedEmulator(_ name: String)

    var userFriendlyMessage: String {
      switch self {
        case .failedToLocateAVDManagerExecutable(let expectedLocation):
          var message = "Failed to locate 'avdmanager' executable"
          if let expectedLocation {
            message += "; expected location was '\(expectedLocation.path)'"
          }
          return message
        case .failedToLocateEmulatorCommandExecutable(let expectedLocation):
          var message = "Failed to locate 'emulator' command executable"
          if let expectedLocation {
            message += "; expected location was '\(expectedLocation.path)'"
          }
          return message
        case .cannotAttachToAlreadyBootedEmulator(let name):
          return "Cannot attach to already booted emulator (name = \(name))"
      }
    }
  }
}
