extension SwiftPackageManager {
  /// A base class for package graph visitors.
  class PackageGraphVisitor {
    /// Begin depth-first traversal of a package graph.
    func visit(_ packageGraph: PackageGraph) {
      seen = []
      doVisit(packageGraph.rootPackage, in: packageGraph)
    }

    /// Override this method to visit a package graph's package in depth-first order.
    /// - Returns: `true` to visit the package's children, `false` otherwise.
    func visit(_ package: Package<PackageReference>) -> Bool {
      return true
    }

    /// Packages that have already been encountered.
    private var seen: Set<PackageReference> = []

    /// The underlying depth-first visiting algorithm.
    private func doVisit(
      _ package: Package<PackageReference>,
      in packageGraph: PackageGraph
    ) {
      guard seen.insert(package.reference).inserted else {
        return
      }

      let shouldVisitDependencies = visit(package)
      guard shouldVisitDependencies else {
        return
      }

      for dependency in package.dependencies {
        do {
          let dependencyPackage = try packageGraph.package(referredToBy: dependency)
          doVisit(dependencyPackage, in: packageGraph)
        } catch {
          log.warning("Failed to locate '\(dependency)' in package graph (skipping)")
        }
      }
    }
  }
}
