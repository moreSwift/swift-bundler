import Foundation
import TOMLKit

/// The Swift Bundler specific configuration of a SwiftPM target.
@Configuration(overlayable: true)
struct TargetConfiguration: Codable, Sendable {
  /// Android-specific configuration.
  var android: Android

  // TODO(stackotter): Make this config merge instead of replace, when partially
  //   supplied in an overlay
  /// Android-specific target configuration.
  @Configuration(overlayable: false)
  struct Android: Codable, Sendable {
    /// The directory to find Java source files in.
    ///
    /// The source files are expected to be within a Java-style package
    /// directory structure. E.g. `<javaDirectory>/com/example/mypackage/MyClass.java`.
    /// If not provided, Swift Bundler will not search for Java sources.
    var javaDirectory: String?
    /// The directory to find Kotlin source files in.
    ///
    /// Defaults to the value of ``javaDirectory``.
    var kotlinDirectory: String?
  }
}
