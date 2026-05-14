import Foundation
import XMLCoder

/// A utility for creating an AppxManifest.Manifest.xml file.
///
/// todo: This doesn't package the MSIX: it only creates the manifest.
enum AppxManifestCreator {
  /// A struct representing the paths to the package's icon files.
  struct IconPaths {
    let square150x150: String
    let square44x44: String
  }

  /// Creates an AppX manifest for the given bundler context.
  /// - Parameters:
  ///   - context: The bundler context.
  ///   - icons: The paths to the package's icon files relative to the package
  ///     root.
  ///   - executablePath: The path to the package's executable relative to the
  ///     package root.
  ///   - outputURL: The URL to write the manifest to.
  static func createManifest(
    for context: BundlerContext,
    withIcons icons: IconPaths,
    executablePath: String,
    outputURL: URL
  ) throws(Error) {
    guard let architecture = context.architectures.first, context.architectures.count == 1 else {
      throw Error(.unknownArchitecture)
    }

    guard let msixConfig = context.appConfiguration.msix else {
      throw Error(.msixFieldsMissing)
    }

    let extensions: [AppxManifest.SomeApplicationExtension] =
      [
        .desktopExtension(
          .fullTrustProcess(
            AppxManifest.ApplicationDesktopFullTrustProcess(executable: executablePath)
          )
        )
      ]
      + (context.appConfiguration.urlSchemes.map { scheme in
        AppxManifest.SomeApplicationExtension.uap3Extension(
          .uap3Protocol(
            .init(name: scheme, displayName: nil, logo: nil)
          )
        )
      })

    let version = context.appConfiguration.version

    let manifest = AppxManifest.Package(
      identity: AppxManifest.Identity(
        name: context.appConfiguration.identifier,
        publisher: msixConfig.publisher,
        version: msixConfig.version?.description
          ?? "\(version.major).\(version.minor).\(version.patch).0",
        processorArchitecture: architecture.msixName
      ),
      properties: AppxManifest.Properties(
        displayName: msixConfig.displayName ?? context.appName,
        publisherDisplayName: msixConfig.publisherDisplayName,
        logo: icons.square150x150
      ),
      resources: [AppxManifest.Resource(language: "en-US")],
      dependencies: [
        .targetDeviceFamily(
          AppxManifest.TargetDeviceFamily(
            name: "Windows.Desktop",
            minimumVersion: "10.0.19041.0",
            maximumVersionTested: "10.0.19041.0"
          )
        )
      ],
      capabilities: [
        .capability(AppxManifest.Capability(name: "runFullTrust"))
      ],
      applications: [
        AppxManifest.Application(
          id: context.appConfiguration.identifier,
          executable: executablePath,
          entryPoint: "Windows.FullTrustApplication",
          uapVisualElements: .init(
            displayName: msixConfig.displayName ?? context.appName,
            description: msixConfig.description ?? context.appConfiguration.appDescription ?? "",
            backgroundColor: msixConfig.backgroundColor ?? "transparent",
            square150x150Logo: icons.square150x150,
            square44x44Logo: icons.square44x44
          ),
          extensions: .init(extensions)
        )
      ]
    )

    let xmlData = try Error.catch(withMessage: .xmlEncodingFailed) {
      try AppxManifest.encodeManifest(manifest)
    }

    do {
      try xmlData.write(to: outputURL)
    } catch {
      throw Error(.failedToWriteManifest(file: outputURL), cause: error)
    }
  }
}
