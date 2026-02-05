import Foundation
import ErrorKit

extension AndroidSDKManager {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``AndroidSDKManager``.
  enum ErrorMessage: Throwable {
    case failedToLocateAndroidSDK(environmentVariable: String, guesses: [URL])
    case sdkMissingBuildTools(sdk: URL)
    case androidHomeDoesNotExist(environmentVariable: String, value: URL)
    case noBuildToolsFound(_ sdk: URL)
    case ndkNotInstalled(_ ndkDirectory: URL)
    case ndkLLVMPrebuiltsOnlyDistributedForX86_64(HostPlatform, BuildArchitecture)
    case ndkMissingNDKPrebuilts(_ prebuiltDirectory: URL)
    case ndkMissingReadelfTool(_ readelfTool: URL)

    var userFriendlyMessage: String {
      switch self {
        case .failedToLocateAndroidSDK(let environmentVariable, let guesses):
          let guesses = ["$\(environmentVariable)"] + guesses.map(\.path)
          let joinedGuesses = guesses.joinedGrammatically()
          return """
            Failed to locate the Android SDK. Tried \(joinedGuesses). If the SDK \
            is correctly installed, set the \(environmentVariable) environment \
            variable to the absolute path of the SDK
            """
        case .sdkMissingBuildTools(let sdk):
          return """
            The Android SDK '\(sdk.path)' is missing a build-tools subdirectory
            """
        case .androidHomeDoesNotExist(let environmentVariable, let value):
          return """
            The \(environmentVariable) environment variable points to a directory \
            that does not exist (\(value)). Either update its value to point to a \
            valid Android SDK, or unset the environment variable and let Swift \
            Bundler attempt to locate the SDK automatically.
            """
        case .noBuildToolsFound(let sdk):
          return """
            No build tools found at ./\(AndroidSDKManager.buildToolsRelativePath) \
            in Android SDK at \(sdk.path) 
            """
        case .ndkNotInstalled(let ndkDirectory):
          return "No NDK installations found. Searched '\(ndkDirectory.path)'"
        case .ndkLLVMPrebuiltsOnlyDistributedForX86_64(let platform, let architecture):
          return """
            NDK LLVM prebuilts are only distributed for x86_64, meaning that \
            Android development is only supported on x86_64 machines and Apple \
            Silicon Macs with Rosetta. \(platform) + \(architecture) is not \
            supported.
            """
        case .ndkMissingNDKPrebuilts(let prebuiltDirectory):
          return """
            Expected NDK LLVM prebuilts to be located at '\(prebuiltDirectory.path)', \
            but the directory does not exist
            """
        case .ndkMissingReadelfTool(let readelfTool):
          return """
            Expected llvm-readelf to be located at '\(readelfTool.path)', but \
            the file does not exist
            """
      }
    }
  }
}
