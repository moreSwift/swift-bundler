import Foundation
import XMLCoder

/// A utility for creating an AppxManifest.xml file.
enum AppxManifestCreator {
  /// The core `<Package>` element of the manifest.
  struct AppxPackage: Codable {
    enum CodingKeys: String, CodingKey {
      case identity = "Identity"
      case properties = "Properties"
      case resources = "Resources"
      case dependencies = "Dependencies"
      case capabilities = "Capabilities"
      case applications = "Applications"
    }

    let identity: AppxIdentity
    let properties: AppxProperties
    let resources: AppxResources
    let dependencies: AppxDependencies
    let capabilities: AppxCapabilities
    let applications: AppxApplications
  }

  /// The `<Identity>` element, which contains identifying information about the
  /// package, such as its name, publisher, version, and architecture.
  struct AppxIdentity: Codable, DynamicNodeEncoding {
    enum CodingKeys: String, CodingKey {
      case name = "Name"
      case publisher = "Publisher"
      case version = "Version"
      case processorArchitecture = "ProcessorArchitecture"
    }

    static func nodeEncoding(for _key: any CodingKey) -> XMLEncoder.NodeEncoding {
      return .attribute
    }

    let name: String
    let publisher: String
    let version: String
    let processorArchitecture: String
  }

  /// The `<Properties>` element, which contains properties of the package.
  struct AppxProperties: Codable {
    enum CodingKeys: String, CodingKey {
      case displayName = "DisplayName"
      case publisherDisplayName = "PublisherDisplayName"
      case logo = "Logo"
    }

    let displayName: String
    let publisherDisplayName: String
    let logo: String
  }

  /// The `<Resources>` element, which contains one or more `<Resource>`
  /// elements that specify the languages supported by the package.
  struct AppxResources: Codable {
    enum CodingKeys: String, CodingKey {
      case resource = "Resource"
    }

    let resource: [AppxResource]
  }

  /// A `<Resource>` element, which specifies a language supported by the
  /// package.
  struct AppxResource: Codable, DynamicNodeEncoding {
    enum CodingKeys: String, CodingKey {
      case language = "Language"
    }

    static func nodeEncoding(for _key: any CodingKey) -> XMLEncoder.NodeEncoding {
      return .attribute
    }

    let language: String
  }

  /// The `<Dependencies>` element, which contains the dependencies of the
  /// package, such as packages or device family dependencies.
  struct AppxDependencies: Codable {
    enum CodingKeys: String, CodingKey {
      case targetDeviceFamily = "TargetDeviceFamily"
      case packageDependency = "PackageDependency"
    }

    let dependencies: [AppxDependency]

    init(_ dependencies: [AppxDependency]) {
      self.dependencies = dependencies
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      for dependency in dependencies {
        switch dependency {
          case .targetDeviceFamily(let value):
            try container.encode(value, forKey: .targetDeviceFamily)
          case .packageDependency(let value):
            try container.encode(value, forKey: .packageDependency)
        }
      }
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      var result: [AppxDependency] = []
      if let families = try container.decodeIfPresent(
        [AppxTargetDeviceFamily].self,
        forKey: .targetDeviceFamily
      ) {
        result.append(contentsOf: families.map(AppxDependency.targetDeviceFamily))
      }
      if let packages = try container.decodeIfPresent(
        [AppxPackageDependency].self,
        forKey: .packageDependency
      ) {
        result.append(contentsOf: packages.map(AppxDependency.packageDependency))
      }
      self.dependencies = result
    }
  }

  /// A single dependency entry inside `<Dependencies>` — either a target
  /// device family or a package dependency.
  enum AppxDependency: Codable {
    case targetDeviceFamily(AppxTargetDeviceFamily)
    case packageDependency(AppxPackageDependency)
  }

  /// A `<TargetDeviceFamily>` element, which specifies a device family that the
  /// package supports.
  struct AppxTargetDeviceFamily: Codable, DynamicNodeEncoding {
    enum CodingKeys: String, CodingKey {
      case name = "Name"
      case minVersion = "MinVersion"
      case maxVersionTested = "MaxVersionTested"
    }

    static func nodeEncoding(for _key: any CodingKey) -> XMLEncoder.NodeEncoding {
      return .attribute
    }

    let name: String
    let minVersion: String
    let maxVersionTested: String
  }

  /// A `<PackageDependency>` element, which specifies a dependency on another
  /// package.
  struct AppxPackageDependency: Codable, DynamicNodeEncoding {
    enum CodingKeys: String, CodingKey {
      case name = "Name"
      case publisher = "Publisher"
      case minVersion = "MinVersion"
    }

    static func nodeEncoding(for _key: any CodingKey) -> XMLEncoder.NodeEncoding {
      return .attribute
    }

    let name: String
    let publisher: String
    let minVersion: String
  }

  /// The `<Capabilities>` element, which contains the capabilities that the
  /// package supports.
  struct AppxCapabilities: Codable {
    enum CodingKeys: String, CodingKey {
      case capability = "rescap:Capability"
    }

    let capability: [AppxCapability]
  }

  /// A `<Capability>` element, which specifies a capability that the package
  /// supports.
  struct AppxCapability: Codable, DynamicNodeEncoding {
    enum CodingKeys: String, CodingKey {
      case name = "Name"
    }

    static func nodeEncoding(for _key: any CodingKey) -> XMLEncoder.NodeEncoding {
      return .attribute
    }

    let name: String
  }

  /// The `<Applications>` element, which contains one or more `<Application>`
  /// elements.
  struct AppxApplications: Codable {
    enum CodingKeys: String, CodingKey {
      case application = "Application"
    }

    let application: [AppxApplication]
  }

  /// An `<Application>` element, which represents an application within the
  /// package.
  struct AppxApplication: Codable, DynamicNodeEncoding {
    enum CodingKeys: String, CodingKey, CaseIterable {
      case id = "Id"
      case executable = "Executable"
      case entryPoint = "EntryPoint"
      case uapVisualElements = "uap:VisualElements"
      case extensions = "Extensions"
    }

    static func nodeEncoding(for key: any CodingKey) -> XMLEncoder.NodeEncoding {
      switch key {
        case CodingKeys.id, CodingKeys.executable, CodingKeys.entryPoint:
          return .attribute
        default:
          return .element
      }
    }

    let id: String
    let executable: String
    let entryPoint: String
    let uapVisualElements: AppxUAPVisualElements?
    let extensions: AppxExtensions?
  }

  /// The `<uap:VisualElements>` element, which contains visual elements for an
  /// application, such as its display name and logos.
  struct AppxUAPVisualElements: Codable, DynamicNodeEncoding {
    enum CodingKeys: String, CodingKey {
      case displayName = "DisplayName"
      case description = "Description"
      case backgroundColor = "BackgroundColor"
      case square150x150Logo = "Square150x150Logo"
      case square44x44Logo = "Square44x44Logo"
    }

    static func nodeEncoding(for _key: any CodingKey) -> XMLEncoder.NodeEncoding {
      return .attribute
    }

    let displayName: String
    let description: String
    let backgroundColor: String
    let square150x150Logo: String
    let square44x44Logo: String
  }

  /// The `<Extensions>` element, which contains one or more extensions for an
  /// application, such as protocol handlers or full trust process declarations.
  struct AppxExtensions: Codable {
    enum CodingKeys: String, CodingKey {
      case uap3Extension = "uap3:Extension"
      case desktopExtension = "desktop:Extension"
    }

    let extensions: [AppxExtension]

    init(_ extensions: [AppxExtension]) {
      self.extensions = extensions
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      for ext in extensions {
        switch ext {
          case .uap3Extension(let value):
            try container.encode(value, forKey: .uap3Extension)
          case .desktopExtension(let value):
            try container.encode(value, forKey: .desktopExtension)
        }
      }
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      var result: [AppxExtension] = []
      if let uap3s = try container.decodeIfPresent(
        [AppxUAP3Extension].self,
        forKey: .uap3Extension
      ) {
        result.append(contentsOf: uap3s.map(AppxExtension.uap3Extension))
      }
      if let desktops = try container.decodeIfPresent(
        [AppxDesktopExtension].self,
        forKey: .desktopExtension
      ) {
        result.append(contentsOf: desktops.map(AppxExtension.desktopExtension))
      }
      self.extensions = result
    }
  }

  /// An `<Extension>` element, which represents an extension for an
  /// application.
  enum AppxExtension: Codable {
    enum CodingKeys: String, CodingKey, XMLChoiceCodingKey {
      case desktopExtension = "desktop:Extension"
      case uap3Extension = "uap3:Extension"
    }

    enum Uap3ExtensionCodingKeys: String, CodingKey { case _0 = "" }
    enum DesktopExtensionCodingKeys: String, CodingKey { case _0 = "" }

    case desktopExtension(AppxDesktopExtension)
    case uap3Extension(AppxUAP3Extension)
  }

  /// A `<desktop:Extension>` element, which represents a extension in the
  /// desktop namespace, such as a full trust process declaration.
  enum AppxDesktopExtension: Codable, DynamicNodeEncoding {
    enum CodingKeys: String, CodingKey {
      case category = "Category"
      case executable = "Executable"

      case fullTrustProcess = "desktop:FullTrustProcess"

      var category: String? {
        switch self {
          case .category, .executable:
            return nil
          case .fullTrustProcess:
            return "windows.fullTrustProcess"
        }
      }
    }

    static func nodeEncoding(for key: any CodingKey) -> XMLEncoder.NodeEncoding {
      switch key {
        case CodingKeys.category, CodingKeys.executable:
          return .attribute
        default:
          return .element
      }
    }

    case fullTrustProcess(AppxDesktopFullTrustProcess)

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let category = try container.decode(String.self, forKey: .category)
      switch category {
        case CodingKeys.fullTrustProcess.category:
          self = .fullTrustProcess(
            try container.decode(AppxDesktopFullTrustProcess.self, forKey: .executable)
          )
        default:
          throw DecodingError.dataCorrupted(
            DecodingError.Context(
              codingPath: decoder.codingPath,
              debugDescription: "Unknown Category '\(category)' on <desktop:Extension>"
            )
          )
      }
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      switch self {
        case .fullTrustProcess(let process):
          try container.encodeIfPresent(CodingKeys.fullTrustProcess.category, forKey: .category)
          try container.encode(process.executable, forKey: .executable)
      }
    }
  }

  /// The `<desktop:FullTrustProcess>` element, which represents a full trust
  /// process declaration in the desktop namespace.
  ///
  /// This Element may not be encoded unless there is a
  /// `<desktop:ParameterGroup>` element contained. This is not supported.
  ///
  /// todo: support `<desktop:ParameterGroup>`.
  struct AppxDesktopFullTrustProcess: Codable, DynamicNodeEncoding {
    enum CodingKeys: String, CodingKey {
      case executable = "Executable"
    }

    static func nodeEncoding(for _key: any CodingKey) -> XMLEncoder.NodeEncoding {
      return .attribute
    }

    let executable: String
  }

  /// An `<uap3:Extension>` element, which represents an extension in the uap3
  /// namespace, such as a protocol handler declaration.
  enum AppxUAP3Extension: Codable, DynamicNodeEncoding {
    enum CodingKeys: String, CodingKey {
      case category = "Category"
      case uap3Protocol = "uap3:Protocol"

      var category: String? {
        switch self {
          case .category:
            return nil
          case .uap3Protocol:
            return "windows.protocol"
        }
      }
    }

    case uap3Protocol(AppxUAP3Protocol)

    static func nodeEncoding(for key: any CodingKey) -> XMLEncoder.NodeEncoding {
      switch key {
        case CodingKeys.category:
          return .attribute
        default:
          return .element
      }
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let category = try container.decode(String.self, forKey: .category)
      switch category {
        case CodingKeys.uap3Protocol.category:
          let protocolData = try container.decode(
            AppxUAP3Protocol.self,
            forKey: .uap3Protocol
          )
          self = .uap3Protocol(protocolData)
        default:
          throw DecodingError.dataCorrupted(
            DecodingError.Context(
              codingPath: decoder.codingPath,
              debugDescription: "Unknown Category '\(category)' on <uap3:Extension>"
            )
          )
      }
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      switch self {
        case .uap3Protocol(let protocolData):
          try container.encodeIfPresent(CodingKeys.uap3Protocol.category, forKey: .category)
          try container.encode(protocolData, forKey: .uap3Protocol)
      }
    }
  }

  /// A `<uap3:Protocol>` element, which represents a protocol handler
  /// declaration.
  struct AppxUAP3Protocol: Codable, DynamicNodeEncoding {
    enum CodingKeys: String, CodingKey {
      case name = "Name"
      case logo = "uap:Logo"
      case displayName = "uap:DisplayName"
    }

    static func nodeEncoding(for key: any CodingKey) -> XMLEncoder.NodeEncoding {
      switch key {
        case CodingKeys.name:
          return .attribute
        default:
          return .element
      }
    }

    let name: String
    let logo: String?
    let displayName: String?
  }

  /// Encodes an `AppxPackage` manifest to XML data.
  /// - Parameter manifest: The manifest to encode.
  /// - Returns: The encoded XML data.
  private static func encodeManifest(_ manifest: AppxPackage) throws -> Data {
    let encoder = XMLEncoder()
    encoder.outputFormatting = []
    return try encoder.encode(
      manifest,
      withRootKey: "Package",
      rootAttributes: [
        "xmlns": "http://schemas.microsoft.com/appx/manifest/foundation/windows10",
        "xmlns:uap": "http://schemas.microsoft.com/appx/manifest/uap/windows10",
        "xmlns:uap3": "http://schemas.microsoft.com/appx/manifest/uap/windows10/3",
        "xmlns:uap5": "http://schemas.microsoft.com/appx/manifest/uap/windows10/5",
        "xmlns:rescap":
          "http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities",
        "xmlns:desktop": "http://schemas.microsoft.com/appx/manifest/desktop/windows10",
        "xmlns:desktop2": "http://schemas.microsoft.com/appx/manifest/desktop/windows10/2",
        "xmlns:virtualization":
          "http://schemas.microsoft.com/appx/manifest/virtualization/windows10",
        "xmlns:com": "http://schemas.microsoft.com/appx/manifest/com/windows10",
        "IgnorableNamespaces": "uap uap3 uap5 rescap desktop desktop2 virtualization com",
      ],
      header: XMLHeader(version: 1.0, encoding: "utf-8")
    )
  }

  /// A struct representing the paths to the package's icon files.
  struct IconPaths {
    let square150x150: String
    let square44x44: String
  }

  /// Creates an AppX manifest for the given bundler context.
  /// - Parameters:
  ///   - context: The bundler context.
  ///   - icons: The paths to the package's icon files relative to the package
  ///            root.
  ///   - executablePath: The path to the package's executable relative to the
  ///                     package root.
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

    let extensions: [AppxExtension] =
      [
        .desktopExtension(.fullTrustProcess(.init(executable: executablePath)))
      ]
      + (context.appConfiguration.urlSchemes.map { scheme in
        AppxExtension.uap3Extension(.uap3Protocol(.init(name: scheme, logo: nil, displayName: nil)))
      })

    let version = context.appConfiguration.version

    let manifest = AppxPackage(
      identity: AppxIdentity(
        name: context.appConfiguration.identifier,
        publisher: msixConfig.publisher,
        version: "\(version.major).\(version.minor).\(version.patch).0",
        processorArchitecture: architecture.windowsName
      ),
      properties: AppxProperties(
        displayName: msixConfig.displayName,
        publisherDisplayName: msixConfig.publisherDisplayName,
        logo: icons.square150x150
      ),
      resources: AppxResources(
        resource: [AppxResource(language: "en-US")]  // todo: configure languages
      ),
      dependencies: AppxDependencies(
        [
          .targetDeviceFamily(
            AppxTargetDeviceFamily(
              name: "Windows.Desktop",
              minVersion: "10.0.19041.0",
              maxVersionTested: "10.0.19041.0"
            )
          )
        ]
          + msixConfig.dependencies.map { dependency in
            AppxDependency.packageDependency(
              AppxPackageDependency(
                name: dependency.name,
                publisher: dependency.publisher,
                minVersion: dependency.minimumVersion.stringValue
              )
            )
          }
      ),
      capabilities: AppxCapabilities(
        capability: [
          AppxCapability(name: "runFullTrust")
        ]
      ),
      applications: AppxApplications(
        application: [
          AppxApplication(
            id: context.appConfiguration.identifier,
            executable: executablePath,
            entryPoint: "Windows.FullTrustApplication",
            uapVisualElements: .init(
              displayName: msixConfig.displayName,
              description: msixConfig.description,
              backgroundColor: msixConfig.backgroundColor,
              square150x150Logo: icons.square150x150,
              square44x44Logo: icons.square44x44
            ),
            extensions: .init(extensions)
          )
        ]
      )
    )

    let xmlData = try Error.catch(withMessage: .xmlEncodingFailed) {
      try encodeManifest(manifest)
    }

    do {
      try xmlData.write(to: outputURL)
    } catch {
      throw Error(.failedToWriteManifest(file: outputURL), cause: error)
    }
  }
}
