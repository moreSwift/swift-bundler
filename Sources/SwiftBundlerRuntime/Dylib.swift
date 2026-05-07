import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

#if canImport(Darwin) || canImport(Glibc)
  /// A dynamic library.
  public struct Dylib {
    private var dylib: UnsafeMutableRawPointer

    /// Opens the dynamic library at the provided path.
    public static func open(_ path: URL) throws -> Dylib {
      guard let dylib = dlopen(path.path, RTLD_NOW | RTLD_LOCAL) else {
        throw DylibError.failedToOpen
      }
      return Dylib(dylib: dylib)
    }

    /// Retrieves a symbol from a dynamic library. Protects against the symbol not
    /// existing, but doesn't protect against type mismatches.
    public func symbol<T>(named name: String, ofType type: T.Type) -> T? {
      guard let symbolPointer = dlsym(dylib, name) else {
        return nil
      }
      return unsafeBitCast(symbolPointer, to: T.self)
    }

    public func close() {
      dlclose(dylib)
    }
  }

  public enum DylibError: LocalizedError {
    case failedToOpen

    public var errorDescription: String? {
      switch self {
        case .failedToOpen:
          return "Failed to open dynamic library"
      }
    }
  }
#endif
