import Foundation

/// The Swift Bundler specific configuration of a SwiftPM target.
@Configuration(overlayable: true)
struct TargetConfiguration: Codable, Hashable, Sendable {
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
  struct Android: Codable, Hashable, Sendable {
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
    /// The directory to find resource files in, such as XML resources.
    ///
    /// If not provided, resource linking is skipped.
    var resourceDirectory: String?
    /// Additional AAPT options.
    var aapt: AAPTOptions?

    /// The Android entry point advertised by this target. Must be a C ABI function.
    ///
    /// If this is the only entry point advertised to an app, then it will be the app's
    /// default Android entry point. This entry point smothers the entry points
    /// defined by the target's dependencies.
    @Introduced(in: "3.1.0")
    var entryPoint: String?

    /// The Android main activity advertised by this target. Must be the fully
    /// qualifieda name of a Java or Kotlin class.
    ///
    /// If this is the only main activity advertised to an app, then it will be the app's
    /// default Android main activity. This main activity smothers the main activities
    /// defined by the target's dependencies.
    @Introduced(in: "3.1.0")
    var mainActivity: String?

    // https://developer.android.com/reference/tools/gradle-api/8.1/com/android/build/api/dsl/AndroidResources
    @Mergeable
    struct AAPTOptions: Codable, Hashable, Sendable, Flattenable {
      var ignoreAssetsPatterns: [String]?
      var noCompress: [String]?
      var failOnMissingConfigEntry: Bool?
      var additionalParameters: [String]?
      var namespaced: Bool?
    
      struct Flat: Hashable, Sendable {
        var ignoreAssetsPatterns: [String]
        var noCompress: [String]
        var failOnMissingConfigEntry: Bool?
        var additionalParameters: [String]
        var namespaced: Bool?
      }
        
      func flatten(with context: ConfigurationFlattener.Context) throws(ConfigurationFlattener.Error) -> Flat {
        Flat(
          ignoreAssetsPatterns: ignoreAssetsPatterns ?? [],
          noCompress: noCompress ?? [],
          failOnMissingConfigEntry: failOnMissingConfigEntry,
          additionalParameters: additionalParameters ?? [],
          namespaced: namespaced
        )
      }
    }
  }
}
