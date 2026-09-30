extension SwiftPackageManager {
  /// A base class for target dependency visitors.
  class TargetDependencyVisitor {
    /// Visit all active dependencies of a given product in depth-first order.
    func visit(
      product: String,
      inPackage package: PackageReference,
      inPackageGraph packageGraph: PackageGraph,
      targetPlatform: Platform
    ) throws(SwiftPackageManager.Error) {
      seen = []
      let directTargets = try packageGraph.targets(ofProduct: product, inPackage: package)
      for target in directTargets {
        try doVisit(target: target, in: packageGraph, withTargetPlatform: targetPlatform)
      }
    }

    /// Override this method to visit each active target dependency.
    func visit(
      _ target: TargetReference,
      packageGraph: PackageGraph
    ) throws(SwiftPackageManager.Error) -> Bool {
      return true
    }

    /// Packages that have already been encountered.
    private var seen: Set<TargetReference> = []

    /// The underlying depth-first visiting algorithm.
    private func doVisit(
      target targetReference: TargetReference,
      in packageGraph: PackageGraph,
      withTargetPlatform targetPlatform: Platform
    ) throws(SwiftPackageManager.Error) {
      guard seen.insert(targetReference).inserted else {
        return
      }

      let shouldVisitDependencies = try visit(targetReference, packageGraph: packageGraph)
      guard shouldVisitDependencies else {
        return
      }

      let dependencies = try packageGraph.directTargetDependencies(
        ofTarget: targetReference.name,
        inPackage: targetReference.package,
        targetPlatform: targetPlatform
      )

      for dependency in dependencies {
        try doVisit(
          target: dependency,
          in: packageGraph,
          withTargetPlatform: targetPlatform
        )
      }
    }
  }
}
