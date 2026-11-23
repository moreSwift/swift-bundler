import Foundation

/// Environment variables that Swift Bundler respects.
enum Env {
  /// Keys corresponding to Swift Bundler environment variables.
  enum Keys {
    /// The key for ``Env/effectiveVersion``.
    static let effectiveVersion = "_SBUN_EFFECTIVE_VERSION"
    /// The key for ``Env/autoUpdateTemplates``.
    static let autoUpdateTemplates = "SBUN_AUTO_UPDATE_TEMPLATES"
  }

  /// An override for Swift Bundler's CLI version. Used to test feature gating
  /// when developing Swift Bundler.
  static var effectiveVersion: Version? {
    getVersion(Keys.effectiveVersion)
  }

  /// Whether to auto update templates or not.
  static var autoUpdateTemplates: Bool {
    getBool(Keys.autoUpdateTemplates) ?? true
  }

  // MARK: Helpers

  static func get(_ key: String) -> String? {
    ProcessInfo.processInfo.environment[key]
  }

  static func getBool(_ key: String) -> Bool? {
    get(key).map { $0 != "0" }
  }

  static func getVersion(_ key: String) -> Version? {
    guard let value = get(key), let version = Version(tolerant: value) else {
      return nil
    }
    return version
  }
}
