extension SwiftPackageManager {
  /// A reference to a target in a package graph.
  struct TargetReference: Sendable, Hashable, CustomStringConvertible {
    /// The name of the target.
    var name: String
    /// A reference to the target's enclosing package.
    var package: PackageReference

    var description: String {
      "\(package.identity).\(name)"
    }
  }
}
