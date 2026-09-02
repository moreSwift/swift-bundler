import Foundation
import Testing
@testable import SwiftBundler

@Suite(.serialized)
struct PackageGraphLoadingTests {
  private func pathURL(_ path: String) -> URL {
    URL(fileURLWithPath: path)
  }

  @Test("Ensure that we can load a simple package graph with two packages")
  func simpleGraphLoading() async throws {
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

  @Test(
    "Ensure that trait-gated dependencies are correctly loaded/ignored",
    arguments: [true, false]
  )
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
  
  @Test(
    """
    Ensure that the final state of the loaded package graph includes all active \
    trait-gated dependencies (regardless of the order that traits were discovered in)
    """,
    arguments: [true, false]
  )
  func testDelayedLoading(_ libraryFirst: Bool) async throws {
    // This package graph should have the same behaviour with both dependency
    // orderings, but if SecondLibrary is second then the package graph
    // loader has to be careful, because it will initially ignore OptionalLibrary
    // because of the MyTrait requirement not being satisfied, and then it will
    // have to reprocess Library once it reaches SecondLibrary and sees that it
    // enables MyTrait.
    let rootURL = URL(forPackage: "MyPackage")
    let loader = MockPackageLoader(
      packages: [
        .mock(
          name: "MyPackage",
          dependencies: libraryFirst
            ? [.mock("Library"), .mock("SecondLibrary")]
            : [.mock("SecondLibrary"), .mock("Library")],
          targets: [
            .executableMock(
              "Tool",
              dependencies: [.productMock("Library"), .productMock("SecondLibrary")]
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
          name: "SecondLibrary",
          dependencies: [.mock("Library", traits: ["MyTrait"])],
          products: [.libraryMock("Library")],
          targets: [
            .libraryMock("SecondLibrary", dependencies: [.productMock("Library")]),
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
      try await withSerialTaskExecutor {
        try await SwiftPackageManager.loadPackageGraph(
          packageDirectory: rootURL,
          configurationContext: .mock,
          toolchain: nil
        )
      }
    }

    #expect(graph.dependencyPackages.keys.contains("MyPackage"))
    #expect(graph.dependencyPackages.keys.contains("Library"))
    #expect(graph.dependencyPackages.keys.contains("SecondLibrary"))
    #expect(graph.dependencyPackages.keys.contains("OptionalLibrary"))
    #expect(graph.ignoredTransitiveDependencies == [])
    #expect(graph.enabledTraits["Library"] == ["default", "MyTrait"])
  }

  @Test("Ensure that traits from inactive dependency edges still get respected")
  func traitsFromUnusedDependencyEdges() async throws {
    let rootURL = URL(forPackage: "MyPackage")
    let remoteURL = URL(string: "https://example.com/packages/remote")!
    let remoteSource = PackageManifest.PackageDependency.Location.sourceControl(url: remoteURL)
    let loader = MockPackageLoader(
      packages: [
        .mock(
          name: "MyPackage",
          dependencies: [
            .mock("Remote", location: remoteSource),
            .mock("Library")
          ],
          targets: [
            .executableMock(
              "Tool",
              dependencies: [
                .productMock("Library"),
                .productMock("Remote"),
              ]
            )
          ]
        ),
        .mock(
          name: "Library",
          dependencies: [.mock("Remote", traits: ["MyTrait"], location: remoteSource)],
          products: [.libraryMock("Library")],
          targets: [.libraryMock("Library")]
        ),
        .mock(
          name: "Remote",
          source: .remote(gitRepository: remoteURL),
          traits: ["MyTrait"],
          products: [.libraryMock("Remote")],
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

    #expect(graph.dependencyPackages.keys.contains("MyPackage"))
    #expect(graph.dependencyPackages.keys.contains("Library"))
    #expect(graph.dependencyPackages.keys.contains("Remote"))
    #expect(graph.enabledTraits["Remote"] == ["default", "MyTrait"])
  }
}
