// IMPORTANT: This file relies on its location within the source tree. See
//   getSwiftBundlerCheckoutRoot

import Foundation

// For forwards slash URL operator and URL.exists()
@testable import SwiftBundler

/// Creates a temporary copy of a fixture and runs the given action against it.
func withFixture(_ name: String, do action: (URL) async throws -> Void) async throws {
  // Ensure that there is a symlink to the Swift Bundler checkout at
  // '../swift-bundler' relative to the fixture.
  let temp = FileManager.default.temporaryDirectory
  let swiftBundlerCheckout = getSwiftBundlerCheckoutRoot()
  let swiftBundlerSymlink = temp / "swift-bundler"
  if !swiftBundlerSymlink.exists()
    || swiftBundlerSymlink.actuallyResolvingSymlinksInPath() != swiftBundlerCheckout
  {
    try? FileManager.default.removeItem(at: swiftBundlerSymlink)
    try FileManager.default.createSymbolicLink(
      at: swiftBundlerSymlink,
      withDestinationURL: swiftBundlerCheckout
    )
  }

  // Create a copy of the fixture
  let fixture = Bundle.module.bundleURL / "Fixtures" / name
  let fixtureCopy = temp / name
  if fixtureCopy.exists() {
    try? FileManager.default.removeItem(at: fixtureCopy)
  }
  try FileManager.default.copyItem(at: fixture, to: fixtureCopy)

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
