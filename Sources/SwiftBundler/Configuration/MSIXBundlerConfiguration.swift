import Foundation

/// MSIX bundler related configuration properties.
@Configuration(overlayable: false)
struct MSIXBundlerConfiguration: Codable, Sendable {
  var displayName: String
  var description: String
  var backgroundColor: String
  var publisher: String
  var publisherDisplayName: String
  var dependencies: [MSIXDependency]?
}
