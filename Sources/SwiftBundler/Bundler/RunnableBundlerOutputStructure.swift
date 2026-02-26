import Foundation

/// A variation on ``BundlerOutputStructure`` validated as runnable, guarantees
/// that the output contains an executable (or at least claims it does).
struct RunnableBundlerOutputStructure {
  /// The bundle itself.
  var bundle: URL
  /// The actual executable file to run when the user instructs Swift Bundler
  /// to run the app.
  var executable: URL

  /// Validates a bundler's output for 'runnability' (i.e. it claims to have
  /// produced an executable).
  init?(_ output: BundlerOutputStructure) {
    guard let executable = output.executable else {
      return nil
    }
    bundle = output.bundle
    self.executable = executable
  }
}
