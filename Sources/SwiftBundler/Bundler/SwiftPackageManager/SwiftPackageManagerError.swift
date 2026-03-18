import Foundation
import ErrorKit

extension SwiftPackageManager {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``SwiftPackageManager``.
  enum ErrorMessage: Throwable {
    case failedToCreatePackageDirectory(URL)
    case failedToGetSwiftVersion
    case invalidSwiftVersionOutput(String)
    case failedToGetProductsDirectory
    case failedToGetLatestSDKPath(Platform)
    case failedToGetTargetInfo(command: String)
    case failedToParseTargetInfo(json: String)
    case failedToParsePackageManifestOutput(json: String)
    case failedToParsePackageManifestToolsVersion
    case failedToReadBuildPlan(path: URL)
    case failedToDecodeBuildPlan
    case failedToComputeLinkingCommand(details: String)
    case failedToRunModifiedLinkingCommand
    case missingDarwinPlatformVersion(Platform)
    case failedToGetToolsVersion
    case invalidToolsVersion(String)
    case swiftPMDoesntSupportUniversalBuildsForPlatform(Platform, [BuildArchitecture])
    case cannotCompileExecutableAsDylibForPlatform(Platform)
    case failedToReadArtifactBundleInfoJSON(URL)
    case failedToParsePackageDump
    case failedToResolveDependencies(URL)
    case missingDependencyCheckout(URL)
    case packageNotFoundInGraph(PackageReference)
    case targetNotFoundInPackage(_ target: String, PackageReference)
    case productNotFoundInPackage(_ product: String, PackageReference)
    case packageIntentionallyExcludedFromPackageGraph(PackageReference)
    case productNotFoundInGraph(String)

    var userFriendlyMessage: String {
      switch self {
        case .failedToCreatePackageDirectory(let directory):
          return "Failed to create package directory at '\(directory.relativePath)'"
        case .failedToGetSwiftVersion:
          return "Failed to get Swift version"
        case .invalidSwiftVersionOutput(let output):
          return "The output of 'swift --version' could not be parsed: '\(output)'"
        case .failedToGetProductsDirectory:
          return "Failed to get products directory"
        case .failedToGetLatestSDKPath(let platform):
          return "Failed to get latest \(platform.rawValue) SDK path"
        case .failedToGetTargetInfo(let command):
          return "Failed to get target info via '\(command)'"
        case .failedToParseTargetInfo:
          return "Failed to parse Swift target info"
        case .failedToParsePackageManifestOutput:
          return "Failed to parse package manifest output"
        case .failedToParsePackageManifestToolsVersion:
          return "Failed to parse package manifest tools version"
        case .failedToReadBuildPlan(let path):
          let buildPlan = path.path(relativeTo: URL(fileURLWithPath: "."))
          return "Failed to read build plan file at '\(buildPlan)'"
        case .failedToDecodeBuildPlan:
          return "Failed to decode build plain"
        case .failedToComputeLinkingCommand(let details):
          return "Failed to compute linking command: \(details)"
        case .failedToRunModifiedLinkingCommand:
          return "Failed to run modified linking commmand"
        case .missingDarwinPlatformVersion(let platform):
          return """
            Missing target platform version for '\(platform.rawValue)' in \
            'Package.swift'. Please update the `Package.platforms` array \
            and try again. Building for Darwin platforms requires a target \
            platform.
            """
        case .failedToGetToolsVersion:
          return "Failed to get Swift package manifest tools version"
        case .invalidToolsVersion(let version):
          return "Invalid Swift tools version '\(version)' (expected a semantic version)"
        case .swiftPMDoesntSupportUniversalBuildsForPlatform(let platform, let architectures):
          // This should only be possible if the user has provided '--no-xcodebuild',
          // so the error message should be pretty clear to users what they've done.
          let clause = platform.isSimulator ? " without xcodebuild" : ""
          return """
            Swift Bundler cannot perform universal builds targeting \
            \(platform.displayName)\(clause); multi-architecture build requested \
            for \(architectures.map(\.rawValue).joinedGrammatically())
            """
        case .cannotCompileExecutableAsDylibForPlatform(let platform):
          return "Cannot compile executable as dylib for platform '\(platform)'"
        case .failedToReadArtifactBundleInfoJSON(let file):
          return "Failed to read artifactbundle's info.json at '\(file.path)'"
        case .failedToParsePackageDump:
          return """
            Failed to parse output of 'swift package dump-package', please file \
            an issue at \(SwiftBundler.newIssueURL)
            """
        case .failedToResolveDependencies(let package):
          let packagePath = package.path(relativeTo: .currentDirectory)
          return """
            Failed to resolve dependencies of Swift package at '\(packagePath)'
            """
        case .missingDependencyCheckout(let checkout):
          return """
            Expected package checkout at '\(checkout.path)' after resolving
            dependencies, but it wasn't found.
            """
        case .packageNotFoundInGraph(let packageReference):
          return """
            Package with identity '\(packageReference.identity)' not found in \
            package graph
            """
        case .targetNotFoundInPackage(let target, let packageReference):
          return """
            Target '\(target)' not found in package with identity \
            '\(packageReference.identity)'
            """
        case .productNotFoundInPackage(let product, let packageReference):
          return """
            Product '\(product)' not found in package with identity \
            '\(packageReference.identity)'
            """
        case .packageIntentionallyExcludedFromPackageGraph(let packageReference):
          return """
            Attempted to access package dependency with identity \
            '\(packageReference.identity)', but it was intentionally excluded \
            when loading the package graph as it was believed to be unused \
            (for the purposes that Swift Bundler needs the package graph for)
            """
        case .productNotFoundInGraph(let name):
          return "Product named '\(name)' not found in package graph"
      }
    }
  }
}
