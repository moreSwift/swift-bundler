/// A non-Mac Apple device or simulator.
struct AppleDevice: Equatable {
  var platform: NonMacApplePlatform
  var name: String
  var id: String
  var status: Device.Status
}
