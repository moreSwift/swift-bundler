import Foundation
import XMLCoder

/// Android related configuration properties.
@Configuration(overlayable: false)
struct AndroidConfiguration: Codable, Sendable {
  /// The default value to use in place of ``minSDK`` when it isn't set.
  static let defaultMinSDK = 28

  /// The Android API version targeted when compiling Swift code.
  var minSDK: Int?

  /// The Android API version that your app is designed for.
  var targetSDK: Int?

  /// The Android SDK to use when compiling your app's supplementary Java/Kotlin
  /// code and producing packages.
  var compileSDK: Int?

  /// The app's version code. If not specified, defaults to the revision number,
  /// or '1' if a revision number cannot be determined.
  ///
  /// See [Version your app][versioning] from the Android developer documentation
  /// for more information on version codes.
  ///
  /// [versioning]: https://developer.android.com/studio/publish/versioning
  var versionCode: Int?

  /// The app's required permissions.
  ///
  /// Permissions take the form 'android.permission.FOO'. If any entries is the array don't
  /// contain a period, then Swift Bundler will prepend 'android.permission.'
  /// automatically. See the [Android Manifest.permission documentation][permissions]
  /// for a full list of supported permissions.
  ///
  /// Permissions can alternatively be specified as TOML tables with a 'name' field, and
  /// an optional 'max_sdk_version' field containing the maximum SDK version at which the
  /// app requires the permission.
  ///
  /// [permissions]: https://developer.android.com/reference/android/Manifest.permission
  var permissions: [Permission]?

  /// An Android manifest permission request.
  struct Permission: Codable, TriviallyFlattenable {
    var name: String
    var maxSDKVersion: Int?

    enum CodingKeys: String, CodingKey {
      case name
      case maxSDKVersion
    }

    init(from decoder: any Decoder) throws {
      do {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        if container.contains(.maxSDKVersion) {
          maxSDKVersion = try container.decode(Int.self, forKey: .maxSDKVersion)
        }
      } catch {
        let container = try decoder.singleValueContainer()
        name = try container.decode(String.self)
      }
    }

    func encode(to encoder: any Encoder) throws {
      if let maxSDKVersion {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(maxSDKVersion, forKey: .maxSDKVersion)
      } else {
        var container = encoder.singleValueContainer()
        try container.encode(name)
      }
    }
  }
}
