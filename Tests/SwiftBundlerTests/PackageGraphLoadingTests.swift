import Foundation
import Testing
@testable import SwiftBundler

@Suite(.serialized)
struct PackageGraphLoadingTests {
  private func pathURL(_ path: String) -> URL {
    URL(fileURLWithPath: path)
  }

  @Test func simpleGraphLoading() async throws {
    let rootURL = URL(forPackage: "MyPackage")
    let loader = MockPackageLoader(
      packages: [
        .mock(
          name: "MyPackage",
          dependencies: [.mock("Library")],
          targets: [
            .executableMock(
              "Tool",
              dependencies: [.productMock("Library")]
            )
          ]
        ),
        .mock(
          name: "Library",
          products: [.libraryMock("Library")],
          targets: [.libraryMock("Library")]
        )
      ]
    )

    let graph = try await SwiftPackageManager.$packageLoader.withValue(loader) {
      try await SwiftPackageManager.loadPackageGraph(
        packageDirectory: rootURL,
        configurationContext: .mock,
        toolchain: nil
      )
    }

    #expect(graph.ignoredTransitiveDependencies.isEmpty)
    #expect(graph.dependencyPackages.keys.contains("MyPackage"))
    #expect(graph.dependencyPackages.keys.contains("Library"))
  }

  @Test(arguments: [true, false])
  func traitGraphLoading(_ traitEnabled: Bool) async throws {
    let rootURL = URL(forPackage: "MyPackage")
    let enabledTraits: Set<String> = traitEnabled ? ["MyTrait"] : ["default"]
    let loader = MockPackageLoader(
      packages: [
        .mock(
          name: "MyPackage",
          dependencies: [.mock("Library", traits: enabledTraits)],
          targets: [
            .executableMock(
              "Tool",
              dependencies: [.productMock("Library")]
            )
          ]
        ),
        .mock(
          name: "Library",
          dependencies: [.mock("OptionalLibrary")],
          traits: ["MyTrait"],
          products: [.libraryMock("Library")],
          targets: [
            .libraryMock(
              "Library",
              dependencies: [
                .productMock("OptionalLibrary", condition: .mock(traits: ["MyTrait"]))
              ]
            )
          ]
        ),
        .mock(
          name: "OptionalLibrary",
          products: [.libraryMock("OptionalLibrary")],
          targets: [.libraryMock("OptionalLibrary")]
        )
      ]
    )

    let graph = try await SwiftPackageManager.$packageLoader.withValue(loader) {
      try await SwiftPackageManager.loadPackageGraph(
        packageDirectory: rootURL,
        configurationContext: .mock,
        toolchain: nil
      )
    }

    #expect(graph.dependencyPackages.keys.contains("MyPackage"))
    #expect(graph.dependencyPackages.keys.contains("Library"))
    #expect(graph.dependencyPackages.keys.contains("OptionalLibrary") == traitEnabled)
    #expect(graph.ignoredTransitiveDependencies == (traitEnabled ? [] : ["optionallibrary"]))
    #expect(graph.enabledTraits["Library"] == enabledTraits)
  }
}
