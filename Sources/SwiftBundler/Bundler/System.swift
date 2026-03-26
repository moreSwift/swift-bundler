import Foundation

/// A utility containing platform-specialized operations.
enum System {
  /// Gets the application support directory for Swift Bundler.
  /// - Returns: The application support directory, or a failure if the directory couldn't be found or created.
  static func getApplicationSupportDirectory() throws(Error) -> URL {
    let directory: URL
    do {
      directory = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: false
      ).appendingPathComponent("dev.stackotter.swift-bundler")
    } catch {
      throw Error(.failedToGetApplicationSupportDirectory, cause: error)
    }

    do {
      try FileManager.default.createDirectory(at: directory)
    } catch {
      throw Error(.failedToCreateApplicationSupportDirectory, cause: error)
    }

    return directory
  }

  /// Gets the tools directory for Swift Bundler. Used to store downloaded
  /// third-party tools, such as rcedit on Windows.
  static func getToolsDirectory() throws(Error) -> URL {
    let applicationSupport = try getApplicationSupportDirectory()
    let toolsDirectory = applicationSupport / "tools"

    do {
      try FileManager.default.createDirectory(at: toolsDirectory)
    } catch {
      throw Error(.failedToCreateToolsDirectory, cause: error)
    }

    return toolsDirectory
  }
}
