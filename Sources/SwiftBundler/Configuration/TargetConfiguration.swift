import Foundation
import TOMLKit

/// The Swift Bundler specific configuration of a SwiftPM target.
@Configuration(overlayable: true)
struct TargetConfiguration: Codable, Sendable {
  /// Dependency identifiers of dependencies built by Swift Bundler before this
  /// build is invoked. Allows for integration with non-SwiftPM build tools, and
  /// applications pulling other applications (e.g. helper applications) into
  /// their build process. Executable dependencies of targets get pulled into the
  /// final root application as helper executables like usual.
  var dependencies: [AppConfiguration.Dependency]?
}
