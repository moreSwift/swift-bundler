import Foundation

enum FileSystem {
  static func cacheDirectory() throws(Error) -> URL {
    let directory = try Error.catch(withMessage: .failedToGetCacheDirectory) {
      try FileManager.default.url(
        for: .cachesDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
    }

    let cacheDirectory = directory / SwiftBundler.identifier
    if !cacheDirectory.exists() {
      try Error.catch(withMessage: .failedToGetCacheDirectory) {
        try FileManager.default.createDirectory(at: cacheDirectory)
      }
    }
    return cacheDirectory
  }

  static func swiftSDKSilosDirectory() throws(Error) -> URL {
    let cacheDirectory = try cacheDirectory()
    let silosDirectory = cacheDirectory / "sdk-silos"
    if !silosDirectory.exists() {
      try Error.catch(withMessage: .failedToCreateSwiftSDKSilosDirectory) {
        try FileManager.default.createDirectory(at: silosDirectory)
      }
    }
    return silosDirectory
  }

  static func swiftSDKSiloDirectory(
    forArtifactIdentifier identifier: String
  ) throws(Error) -> URL {
    let silos = try swiftSDKSilosDirectory()
    let silo = silos / identifier
    if !silo.exists() {
      try Error.catch(withMessage: .failedToCreateSwiftSDKSiloDirectory(silo)) {
        try FileManager.default.createDirectory(at: silo)
      }
    }
    return silo
  }
}
