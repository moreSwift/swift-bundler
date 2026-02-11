/// A connected android device.
struct ConnectedAndroidDevice: Sendable, Equatable {
  var id: String
  var name: String
  var isEmulator: Bool
  var status: Status

  /// The status of a connected Android device.
  enum Status: Sendable, Hashable {
    case available
    case unavailable
  }
}
