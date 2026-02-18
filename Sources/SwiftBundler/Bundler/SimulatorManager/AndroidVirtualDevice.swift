/// An Android Virtual Device (aka an AVD).
struct AndroidVirtualDevice: Hashable, Sendable {
  /// The emulator's ADB identifier if the emulator has been booted.
  var adbIdentifier: String?
  /// The emulator's AVD name.
  var name: String
}
