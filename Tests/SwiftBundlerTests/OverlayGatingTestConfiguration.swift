import Foundation
import Version

@testable import SwiftBundler

/// A minimal overlayable configuration used to test version gating of
/// properties set within overlays.
///
/// This deliberately lives in its own file without importing TOMLKit, because
/// the `@Configuration` macro expansion refers to Swift Bundler's internal
/// `TOMLValue` type without qualifying it.
@Configuration(overlayable: true)
struct OverlayGatingTestConfiguration: Codable {
  var value: String?

  @Introduced(in: "3.1.0")
  var newValue: String?

  @Available(.platform("linux"))
  @Introduced(in: "3.1.0")
  var newLinuxValue: Bool = false
}
