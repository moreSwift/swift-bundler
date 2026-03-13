import Foundation

#if os(Linux)
  import Glibc
#endif

extension URL {
  /// Gets the path of this URL relative to another URL.
  /// - Parameter base: The base for the relative path.
  /// - Returns: The relative path if both this URL and the base URL are files,
  ///   otherwise the result is undefined. It used to return `nil` in that case,
  ///   but since I know I'll be moving to a proper file path type soon, I won't
  ///   clog up new code with the issues of `URL`.
  func path(relativeTo base: URL) -> String {
    let destComponents = self.pathComponents
    let baseComponents = base.pathComponents

    // If we're on Windows and the URLs point to two different drives,
    // just return the full absolute path.
    if HostPlatform.hostPlatform == .windows,
      destComponents.count >= 2,
      baseComponents.count >= 2,
      destComponents[0] == "/",
      baseComponents[0] == "/",
      // The drive letters follow the `/` component.
      destComponents[1] != baseComponents[1]
    {
      return self.path
    }

    // Find number of common path components:
    var commonComponentCount = 0
    while commonComponentCount < destComponents.count
      && commonComponentCount < baseComponents.count
      && destComponents[commonComponentCount] == baseComponents[commonComponentCount]
    {
      commonComponentCount += 1
    }

    // Build relative path:
    var relComponents = Array(repeating: "..", count: baseComponents.count - commonComponentCount)
    if relComponents.isEmpty {
      relComponents.append(".")
    }
    relComponents.append(contentsOf: destComponents[commonComponentCount...])
    return relComponents.joined(separator: "/")
  }

  /// The date at which the underlying file or directory was last modified, if
  /// the file exists and the date can be retrieved.
  var lastModified: Date? {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
      return nil
    }
    return attributes[FileAttributeKey.modificationDate] as? Date
  }

  /// The current directory.
  static var currentDirectory: URL {
    URL(fileURLWithPath: ".")
  }

  /// ``URL/resolvingSymlinksInPath()`` is broken on Linux, and that's why I
  /// created this function. Tl;dr, if the last path component is a symlink it
  /// doesn't seem to get resolved (at least in the cases I've tried). I don't
  /// know whether this is just some Linux systems or all Linux systems, and I
  /// also don't know whether it's just my Swift version or all Swift versions.
  func actuallyResolvingSymlinksInPath() -> URL {
    #if os(Linux)
      let resolvedPath = String(unsafeUninitializedCapacity: 4097) { buffer in
        realpath(self.path, buffer.baseAddress)
        return strlen(UnsafePointer(buffer.baseAddress!))
      }
      return URL(fileURLWithPath: resolvedPath)
    #else
      return resolvingSymlinksInPath()
    #endif
  }

  /// Gets whether the URL exists on disk or not.
  func exists() -> Bool {
    FileManager.default.fileExists(atPath: path)
  }

  /// Gets whether the URL exists on disk with the given type or not.
  func exists(withType type: FileManager.ItemType) -> Bool {
    FileManager.default.itemExists(at: self, withType: type)
  }

  /// Returns a copy of the URL with its path extension replaced.
  func replacingPathExtension(with newExtension: String) -> URL {
    deletingPathExtension().appendingPathExtension(newExtension)
  }
}

/// Appends a path component to the end of a URL. Think of it like the actual
/// forward slash in paths (sorry Windows).
func / (_ left: URL, _ right: String) -> URL {
  left.appendingPathComponent(right)
}
