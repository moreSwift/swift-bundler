import Foundation

/// The Swift Bundler specific configuration of a SwiftPM target.
@Configuration(overlayable: true)
struct TargetConfiguration: Codable, Sendable {
  /// Dependency identifiers of dependencies built by Swift Bundler before this
  /// build is invoked. Allows for integration with non-SwiftPM build tools, and
  /// applications pulling other applications (e.g. helper applications) into
  /// their build process. Executable dependencies of targets get pulled into the
  /// final root application as helper executables like usual.
  var dependencies: [AppConfiguration.Dependency]?

  /// Android-specific configuration.
  var android: Android?

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
