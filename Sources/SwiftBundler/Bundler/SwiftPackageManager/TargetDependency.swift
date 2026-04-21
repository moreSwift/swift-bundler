extension SwiftPackageManager {
  /// A dependency of a package target.
  enum TargetDependency: Codable, Sendable, Hashable {
    /// A dependency on another target within the same package.
    case target(name: String, condition: Condition?)
    /// A dependency on a product within the same package or a dependency of the package.
    case product(packageIdentity: String, product: String, condition: Condition?)

    /// A condition that must be satisfied for a target dependency to be active.
    enum Condition: Codable, Sendable, Hashable {
      /// A condition that's only active when the target platform is contained
      /// within `names`.
      case platform(names: [String])

      /// Gets whether the condition is satisfied when targeting the given platform.
      /// - Parameter targetPlatform: The target platform.
      /// - Returns: Whether the condition is satisfied.
      func isSatisfied(targetPlatform: Platform) -> Bool {
        switch self {
          case .platform(let names):
            names.contains(targetPlatform.os.manifestConditionName)
        }
      }
    }
  }
}
