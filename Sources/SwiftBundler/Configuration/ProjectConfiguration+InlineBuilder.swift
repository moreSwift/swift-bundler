import Foundation
import Version

extension ProjectConfiguration {
  /// Inline builder definitions were never part of an official release, but
  /// were in the project for a substantial length of time. As such, we have
  /// kept around support for them. This lives in a separate file to keep it
  /// separate from the actual up-to-date configuration format definitions.
  @Configuration(overlayable: false)
  struct InlineBuilder: Codable {
    var name: String
    var type: BuilderType
    @ExcludeFromFlat
    var apiSource: Source?
    @ExcludeFromFlat
    var api: APIRequirement?

    enum BuilderType: String, Codable, TriviallyFlattenable {
      case wholeProject
    }

    @Aggregate("api")
    func flattenAPI(with context: ConfigurationFlattener.Context)
      throws(ConfigurationFlattener.Error)
      -> ProjectConfiguration.Source.FlatWithDefaultRepository
    {
      try ConfigurationFlattener.Error.catch {
        try apiSource.flatten(
          withRequirement: self.api,
          requirementField: context.codingPath.appendingKey(CodingKeys.api)
        )
      }
    }
  }
}

extension ProjectBuilder {
  static let inlineBuilderProductName = "Builder"

  /// Creates a temporary package used to build an inline script-based builder.
  static func prepareInlineBuilder(
    forInlineBuilder builder: ProjectConfiguration.InlineBuilder.Flat,
    packageDirectory: URL,
    scratchDirectory: ScratchDirectoryStructure
  ) async throws(Error) -> OnDiskBuilder {
    // Create builder source file symlink
    try Error.catch(withMessage: .failedToSymlinkBuilderSourceFile) {
      let masterBuilderSourceFile = packageDirectory / builder.name
      if FileManager.default.fileExists(atPath: scratchDirectory.builderSourceFile.path) {
        try FileManager.default.removeItem(at: scratchDirectory.builderSourceFile)
      }
      try FileManager.default.createSymbolicLink(
        at: scratchDirectory.builderSourceFile,
        withDestinationURL: masterBuilderSourceFile
      )
    }

    // Create/update the builder's Package.swift
    let toolsVersion = try await Error.catch {
      try await SwiftPackageManager.getToolsVersion(packageDirectory)
    }

    let manifestContents = generateBuilderPackageManifest(
      toolsVersion,
      builderAPI: builder.api.normalized(
        usingDefault: SwiftBundler.gitURL
      ),
      rootPackageDirectory: packageDirectory,
      builderPackageDirectory: scratchDirectory.builder
    )

    try Error.catch(withMessage: .failedToWriteBuilderManifest) {
      try manifestContents.write(to: scratchDirectory.builderManifest)
    }

    return OnDiskBuilder(
      name: builder.name,
      product: inlineBuilderProductName,
      packageRoot: scratchDirectory.builder
    )
  }

  static func generateBuilderPackageManifest(
    _ swiftVersion: Version,
    builderAPI: ProjectConfiguration.Source.Flat,
    rootPackageDirectory: URL,
    builderPackageDirectory: URL
  ) -> String {
    let dependency: String
    switch builderAPI {
      case .local(let path):
        let fullPath = rootPackageDirectory / path
        let relativePath = fullPath.path(relativeTo: builderPackageDirectory)
        dependency = """
                  .package(
                      name: "swift-bundler",
                      path: "\(relativePath)"
                  )
          """
      case .git(let url, let requirement):
        let revision: String
        switch requirement {
          case .revision(let value):
            revision = value
        }
        dependency = """
                  .package(
                      url: "\(url.absoluteString)",
                      revision: "\(revision)"
                  )
          """
    }

    return """
      // swift-tools-version:\(swiftVersion.major).\(swiftVersion.minor)
      import PackageDescription

      let package = Package(
          name: "Builder",
          platforms: [.macOS(.v10_15)],
          products: [
              .executable(name: "Builder", targets: ["Builder"])
          ],
          dependencies: [
      \(dependency)
          ],
          targets: [
              .executableTarget(
                  name: "\(inlineBuilderProductName)",
                  dependencies: [
                      .product(name: "SwiftBundlerBuilders", package: "swift-bundler")
                  ]
              )
          ]
      )
      """
  }
}
