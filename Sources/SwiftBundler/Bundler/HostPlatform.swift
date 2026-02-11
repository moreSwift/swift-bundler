/// A supported Swift Bundler host platform.
enum HostPlatform: Sendable, Hashable {
  case macOS
  case linux
  case windows

  /// The platform's reprsentation in the regular ``Platform`` enum.
  var platform: Platform {
    switch self {
      case .macOS:
        return .macOS
      case .linux:
        return .linux
      case .windows:
        return .windows
    }
  }

  /// The platform that Swift Bundler is currently running on.
  static var hostPlatform: Self {
    #if os(macOS)
      return .macOS
    #elseif os(Linux)
      return .linux
    #elseif os(Windows)
      return .windows
    #endif
  }

  /// Computes the file name (with file extension) that an executable
  /// with the given base name (no file extension) would have on the
  /// given host platform.
  func executableFileName(forBaseName baseName: String) -> String {
    switch self {
      case .windows:
        return "\(baseName).exe"
      case .macOS, .linux:
        return baseName
    }
  }
}
