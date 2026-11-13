import Foundation

extension CLIConfiguration {
  /// Android related configuration properties.
  @Configuration(overlayable: false)
  struct Android: Codable, Hashable, Sendable {
    /// The default value to use in place of ``minSDK`` when it isn't set.
    static let defaultMinSDK = 28

    /// The Android API version targeted when compiling Swift code.
    var minSDK: Int?
  }
}
