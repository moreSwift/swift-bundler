import Version

extension Version {
  /// A representation of the version using underscore separators and only including down to the least
  /// significant non-zero component.
  ///
  /// For example, `0.5.0` becomes `0_5` and `1.5.2` becomes `1_5_2`.
  var underscoredMinimal: String {
    var string = "\(major)"
    if minor != 0 {
      string += "_\(minor)"
      if patch != 0 {
        string += "_\(patch)"
      }
    }
    return string
  }

  /// The default fallback version to use when we fail to parse a version
  /// or the user doesn't supply one.
  static let defaultFallback = Version(0, 1, 0)

  /// Parses a version or falls back to ``Self/defaultFallback``.
  ///
  /// Exists as a standalone method because we do it in a few places and
  /// the logging of the warning makes the code a bit verbose.
  static func parseOrFallback(_ string: String) -> Version {
    if let version = Version(tolerant: string) {
      return version
    } else {
      log.warning("Failed to parse version '\(string)', falling back to \(defaultFallback)")
      return defaultFallback
    }
  }
}

extension Version: TriviallyFlattenable {}
