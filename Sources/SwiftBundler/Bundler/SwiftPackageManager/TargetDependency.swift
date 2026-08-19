extension SwiftPackageManager {
  /// A dependency of a package target.
  enum TargetDependency: Codable, Sendable, Hashable {
    /// A dependency on another target within the same package.
    case target(name: String, condition: Condition?)
    /// A dependency on a product within the same package or a dependency of the package.
    case product(packageIdentity: String, product: String, condition: Condition?)

    /// A condition that must be satisfied for a target dependency to be active.
    struct Condition: Codable, Sendable, Hashable {
      /// If the platforms array is non-empty, then the condition requires the
      /// current platform to be contained within this array.
      var platforms: [String]
      /// If the traits array is non-empty, then the condition requires at least
      /// one of the listed traits to be enabled.
      var traits: [String]

      /// Checks whether the condition is satisfied when targeting the given platform
      /// with the given traits enabled.
      /// - Parameters:
      ///   - targetPlatform: The target platform.
      ///   - enabledTraits: The traits enabled for this package (including
      ///     traits transitively enabled by 'compound' traits).
      /// - Returns: Whether the condition is satisfied.
      func isSatisfied(targetPlatform: Platform, enabledTraits: Set<String>) -> Bool {
        platformClauseIsSatisfied(by: targetPlatform)
          && traitClauseIsSatisfied(by: enabledTraits)
      }

      /// Checks whether the platform clause of the condition is satisfied by
      /// the given target platform.
      func platformClauseIsSatisfied(by targetPlatform: Platform) -> Bool {
        platforms.isEmpty
          || platforms.contains(targetPlatform.os.manifestConditionName)
      }

      /// Checks whether the traits clause of the condition is satisfied by
      /// the given set of enabled traits.
      func traitClauseIsSatisfied(by enabledTraits: Set<String>) -> Bool {
        // Ref: https://github.com/swiftlang/swift-package-manager/blob/05d6386648965d201676805b206c424008097f0b/Sources/PackageModel/Manifest/Manifest%2BTraits.swift#L393
        traits.isEmpty
          || !enabledTraits.intersection(traits).isEmpty
      }
    }
  }
}
