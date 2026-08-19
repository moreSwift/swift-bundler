extension SwiftPackageManager {
  /// A conditional reference to a target.
  struct ConditionalTargetReference: Sendable, Hashable {
    /// A reference to the underlying target.
    var target: TargetReference
    /// Conditions that dictate when this reference should be counted as
    /// active. Every condition must be satisfied for the target reference
    /// to be considered active. No conditions implies that the reference
    /// is unconditionally active.
    var conditions: [Condition] = []

    /// A condition that makes up part of a conditional target reference.
    struct Condition: Sendable, Hashable {
      /// The package to use when evaluating trait-based conditions.
      var package: PackageReference
      /// The underlying target condition.
      var condition: TargetDependency.Condition
    }

    /// Creates a conditional reference to the given target with the given
    /// conditions.
    init(target: TargetReference, conditions: [Condition]) {
      self.target = target
      self.conditions = conditions
    }

    /// Creates a conditional reference to a target with an associated target
    /// dependency condition. The target dependency condition must be from
    /// the same package as the target, otherwise trait-based conditions won't
    /// get evaluated correctly.
    init(target: TargetReference, condition: TargetDependency.Condition?) {
      self.target = target
      self.conditions = [condition]
        .compactMap { $0 }
        .map { condition in
          Condition(package: target.package, condition: condition)
        }
    }

    /// Gets the reference with the given target conditions appended to its
    /// existing conditions. Target conditions need to be associated with the
    /// package that they came from in order for trait conditions to get
    /// evaluated correctly.
    func appendingConditions(
      _ conditions: [TargetDependency.Condition],
      from package: PackageReference
    ) -> Self {
      var reference = self
      reference.conditions += conditions.map { condition in
        Condition(package: package, condition: condition)
      }
      return reference
    }

    /// Gets the reference with the given conditions appended to its existing
    /// conditions.
    func appendingConditions(_ conditions: [Condition]) -> Self {
      var reference = self
      reference.conditions += conditions
      return reference
    }

    /// Computes whether a conditional reference is active.
    func isActive(targetPlatform: Platform, packageGraph: PackageGraph) -> Bool {
      conditions.allSatisfy { condition in
        condition.condition.isSatisfied(
          targetPlatform: targetPlatform,
          // The conditions that make up a conditional target reference may
          // come from multiple different packages (because they represent
          // all of the conditions present in a chain from the root package
          // to the desired target). The traits used to evaluate each
          // condition must be for the package that the condition originated
          // from.
          enabledTraits: packageGraph.enabledTraits[condition.package] ?? []
        )
      }
    }
  }
}
