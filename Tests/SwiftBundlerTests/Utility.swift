// IMPORTANT: This file relies on its location within the source tree. See
//   getSwiftBundlerCheckoutRoot

import Foundation

// For forwards slash URL operator and URL.exists()
@testable import SwiftBundler

/// Creates a temporary copy of a fixture and runs the given action against it.
func withFixture(_ name: String, do action: (URL) async throws -> Void) async throws {
  // Ensure that there is a copy of the enclosing Swift Bundler checkout at
  // '../swift-bundler' relative to the fixture. We used to use a symlink instead
  // of a proper copy, but that led to deadlocks when the test code tried to invoke
  // SwiftPM commands in the main Swift Bundler checkout (while `swift test` was of
  // course still running).
  let temp = FileManager.default.temporaryDirectory
  let swiftBundlerCheckout = getSwiftBundlerCheckoutRoot()
  let swiftBundlerDirectory = temp / "swift-bundler"
  if swiftBundlerDirectory.exists() {
    try FileManager.default.removeItem(at: swiftBundlerDirectory)
  }

  // Copy non-hidden items over to the fixture copy of the Swift Bundler checkout
  try FileManager.default.createDirectory(at: swiftBundlerDirectory)
  let swiftBundlerContents = try FileManager.default.contentsOfDirectory(at: swiftBundlerCheckout)
  for item in swiftBundlerContents {
    let name = item.lastPathComponent
    guard !name.hasPrefix(".") else {
      continue
    }

    try FileManager.default.copyItem(at: item, to: swiftBundlerDirectory / name)
  }

  // Create a copy of the fixture
  let fixture = Bundle.module.bundleURL / "Fixtures" / name
  let fixtureCopy = temp / name
  let buildDirectory = fixtureCopy / ".build"
  let savedBuildDirectory: URL?
  if fixtureCopy.exists() {
    if buildDirectory.exists() {
      let buildDirectoryBackup = temp / "\(name)-build-dir-backup"
      if buildDirectoryBackup.exists() {
        try FileManager.default.removeItem(at: buildDirectoryBackup)
      }
      try FileManager.default.copyItem(at: buildDirectory, to: buildDirectoryBackup)
      savedBuildDirectory = buildDirectoryBackup
    } else {
      savedBuildDirectory = nil
    }

    try FileManager.default.removeItem(at: fixtureCopy)
  } else {
    savedBuildDirectory = nil
  }
  try FileManager.default.copyItem(at: fixture, to: fixtureCopy)

  // Restore .build directory (saves time for consecutive tests)
  if let savedBuildDirectory {
    try FileManager.default.copyItem(at: savedBuildDirectory, to: buildDirectory)
  }

  defer {
    try? FileManager.default.removeItem(at: fixtureCopy)
  }

  do {
    try await action(fixtureCopy)
  } catch {
    throw error
  }
}

/// Gets the path of the Swift Bundler checkout that the tests were compiled from.
func getSwiftBundlerCheckoutRoot() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}
