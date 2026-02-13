/// An Android device or emulator.
struct AndroidDevice: Sendable, Equatable {
  var id: String
  var name: String
  var isEmulator: Bool
  var status: Device.Status
}
