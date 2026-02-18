/// A non-Mac Apple device or simulator.
struct AppleDevice: Sendable, Equatable {
  var platform: NonMacApplePlatform
  var name: String
  var id: String
  var status: Device.Status
  var architecture: BuildArchitecture
}
