import Foundation

/// MSIX bundler related configuration properties.
@Configuration(overlayable: false)
struct MSIXBundlerConfiguration: Codable, Sendable {
  var version: MSIXVersion?
  var displayName: String?
  var description: String?
  var backgroundColor: String?
  var publisher: String
  var publisherDisplayName: String
}
