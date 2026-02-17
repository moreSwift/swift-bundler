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
    case failedToInstallAPK(URL, ConnectedDevice)
    case failedToLaunchApp(_ identifier: String, ConnectedDevice)
    case failedToGetAppUID(_ identifier: String, ConnectedDevice)
    case failedToParseAppUIDOutput(_ output: String)
    case failedToConnectToLogcat(_ uid: Int, ConnectedDevice)

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
        case .failedToInstallAPK(let apk, let device):
          let apkPath = apk.path(relativeTo: .currentDirectory)
          return """
            Failed to install '\(apkPath)' on device '\(device.identifier)'
            """
        case .failedToLaunchApp(let identifier, let device):
          return "Failed to launch '\(identifier)' on '\(device.identifier)'"
        case .failedToGetAppUID(let identifier, let device):
          return """
            Failed to get UID of app '\(identifier)' on device \
            '\(device.identifier)'
            """
        case .failedToParseAppUIDOutput(let output):
          return "Failed to parse app UID output from ADB: '\(output)'"
        case .failedToConnectToLogcat(let uid, let device):
          return """
            Failed to connect to logcat output of app with UID \(uid) on \
            device '\(device.identifier)'
            """
      }
    }
  }
}
