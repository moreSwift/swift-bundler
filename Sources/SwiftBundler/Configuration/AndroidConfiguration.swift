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
}
