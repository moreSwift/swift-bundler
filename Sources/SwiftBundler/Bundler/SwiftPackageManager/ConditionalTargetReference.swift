extension SwiftPackageManager {
  /// A conditional reference to a target.
  struct ConditionalTargetReference: Sendable, Hashable {
    /// A reference to the underlying target.
    var target: TargetReference
    /// A condition which dictates when this reference should be counted as
    /// active. No conditions implies that the reference is unconditional.
    var conditions: [TargetDependency.Condition]

    /// Gets the reference with the given conditions appended to its existing
    /// conditions.
    func appendingConditions(_ conditions: [TargetDependency.Condition]) -> Self {
      var reference = self
      reference.conditions += conditions
      return reference
    }
  }
}
