import Foundation

/// Describes the basic structure of a bundler's output. Shouldn't describe
/// intermediate files, only the useful final outputs of the bundler.
struct BundlerOutputStructure {
  /// The bundle itself.
  var bundle: URL
  /// The actual executable file to run when the user instructs Swift Bundler
  /// to run the app. If `nil`, it's assumed that the bundler doesn't support
  /// running.
  var executable: URL?
  /// Any other files produced that might be useful wnen distributing the app,
  /// e.g. a `.desktop` file on Linux.
  var additionalOutputs: [URL] = []
}
