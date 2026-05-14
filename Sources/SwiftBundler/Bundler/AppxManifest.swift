import Foundation
import XMLCoder

enum AppxManifest {
  /// The core `<Package>` element of the manifest.
  struct Package: Hashable, Equatable, Codable {
    enum CodingKeys: String, CodingKey {
      case identity = "Identity"
      case properties = "Properties"
      case resources = "Resources"
      case dependencies = "Dependencies"
      case capabilities = "Capabilities"
      case applications = "Applications"
    }

    @Element var identity: Identity
    @Element var properties: Properties
    @Element var resources: [Resource]
    var dependencies: [SomeDependency]
    var capabilities: [SomeCapability]
    var applications: [Application]

    /// Custom decoder to ensure that missing elements are decoded as empty
    /// arrays.
    /// - Parameter decoder: The decoder to decode from.
    /// - Throws: An error if decoding fails.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      _identity = try container.decode(
        Element<Identity>.self,
        forKey: .identity
      )
      _properties = try container.decode(
        Element<Properties>.self,
        forKey: .properties
      )
      _resources = Element(
        try container.decodeIfPresent(
          Element<Resources>.self,
          forKey: .resources
        )?.wrappedValue.resources ?? []
      )
      dependencies =
        try container.decodeIfPresent(
          Element<Dependencies>.self,
          forKey: .dependencies
        )?.wrappedValue.dependencies ?? []
      capabilities =
        try container.decodeIfPresent(
          Element<Capabilities>.self,
          forKey: .capabilities
        )?.wrappedValue.capabilities ?? []
      applications =
        try container.decodeIfPresent(
          Element<Applications>.self,
          forKey: .applications
        )?.wrappedValue.applications ?? []
    }

    /// Creates a new `Package` with the given properties.
    /// - Parameters:
    ///   - identity: The `<Identity>` element of the manifest.
    ///   - properties: The `<Properties>` element of the manifest.
    ///   - resources: The `<Resources>` element of the manifest.
    ///   - dependencies: The `<Dependencies>` element of the manifest.
    ///   - capabilities: The `<Capabilities>` element of the manifest.
    ///   - applications: The `<Applications>` element of the manifest.
    init(
      identity: Identity,
      properties: Properties,
      resources: [Resource],
      dependencies: [SomeDependency],
      capabilities: [SomeCapability],
      applications: [Application]
    ) {
      self._identity = Element(identity)
      self._properties = Element(properties)
      self._resources = Element(resources)
      self.dependencies = dependencies
      self.capabilities = capabilities
      self.applications = applications
    }

    /// Custom encoder to ensure that empty elements are not encoded.
    /// - Parameter encoder: The encoder to encode to.
    /// - Throws: An error if encoding fails.
    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(_identity, forKey: .identity)
      try container.encode(_properties, forKey: .properties)
      if !resources.isEmpty {
        try container.encode(Element(Resources(resources)), forKey: .resources)
      }
      if !dependencies.isEmpty {
        try container.encode(Element(Dependencies(dependencies)), forKey: .dependencies)
      }
      if !capabilities.isEmpty {
        try container.encode(Element(Capabilities(capabilities)), forKey: .capabilities)
      }
      if !applications.isEmpty {
        try container.encode(Element(Applications(applications)), forKey: .applications)
      }
    }
  }

  /// The `<Identity>` element, which contains identifying information about the
  /// package, such as its name, publisher, version, and architecture.
  struct Identity: Hashable, Equatable, Codable {
    enum CodingKeys: String, CodingKey {
      case name = "Name"
      case publisher = "Publisher"
      case version = "Version"
      case processorArchitecture = "ProcessorArchitecture"
    }

    @Attribute var name: String
    @Attribute var publisher: String
    @Attribute var version: String
    @Attribute var processorArchitecture: String

    /// Creates a new `Identity` with the given properties.
    /// - Parameters:
    ///   - name: The name of the package.
    ///   - publisher: The publisher of the package.
    ///   - version: The version of the package.
    ///   - processorArchitecture: The processor architecture of the package.
    init(
      name: String,
      publisher: String,
      version: String,
      processorArchitecture: String
    ) {
      self._name = Attribute(name)
      self._publisher = Attribute(publisher)
      self._version = Attribute(version)
      self._processorArchitecture = Attribute(processorArchitecture)
    }
  }

  /// The `<Properties>` element, which contains properties of the package.
  struct Properties: Hashable, Equatable, Codable {
    enum CodingKeys: String, CodingKey {
      case displayName = "DisplayName"
      case publisherDisplayName = "PublisherDisplayName"
      case logo = "Logo"
    }

    @Element var displayName: String
    @Element var publisherDisplayName: String
    @Element var logo: String

    /// Creates a new `Properties` with the given properties.
    /// - Parameters:
    ///   - displayName: The display name of the package.
    ///   - publisherDisplayName: The display name of the publisher.
    ///   - logo: The path to the logo file.
    init(
      displayName: String,
      publisherDisplayName: String,
      logo: String
    ) {
      self._displayName = Element(displayName)
      self._publisherDisplayName = Element(publisherDisplayName)
      self._logo = Element(logo)
    }
  }

  /// The `<Resources>` element, which contains one or more `<Resource>`
  /// elements that specify the languages supported by the package.
  struct Resources: Hashable, Equatable, Codable {
    enum CodingKeys: String, CodingKey {
      case resources = "Resource"
    }

    var resources: [Resource]

    /// Creates a new `Resources` with the given resources.
    /// - Parameter resource: The list of resource elements.
    init(_ resource: [Resource]) {
      self.resources = resource
    }
  }

  /// A `<Resource>` element, which specifies a language supported by the
  /// package.
  struct Resource: Hashable, Equatable, Codable {
    enum CodingKeys: String, CodingKey {
      case language = "Language"
    }

    @Attribute var language: String

    /// Creates a new `Resource` with the given language.
    /// - Parameter language: The language of the resource, in BCP 47 format.
    init(language: String) {
      self._language = Attribute(language)
    }
  }

  /// The `<Dependencies>` element, which contains the dependencies of the
  /// package, such as packages or device family dependencies.
  struct Dependencies: Hashable, Equatable, Codable {
    enum CodingKeys: String, CodingKey {
      case dependencies = ""
    }

    @Element var dependencies: [SomeDependency]

    /// Creates a new `Dependencies` with the given dependencies.
    /// - Parameter dependencies: The list of dependencies.
    init(_ dependencies: [SomeDependency]) {
      self._dependencies = Element(dependencies)
    }
  }

  /// A single dependency entry inside `<Dependencies>` — either a target
  /// device family or a package dependency.
  enum SomeDependency: Hashable, Equatable, Codable {
    enum CodingKeys: String, CodingKey, XMLChoiceCodingKey {
      case targetDeviceFamily = "TargetDeviceFamily"
      case packageDependency = "PackageDependency"
    }
    enum TargetDeviceFamilyCodingKeys: String, CodingKey { case _0 = "" }
    enum PackageDependencyCodingKeys: String, CodingKey { case _0 = "" }

    case targetDeviceFamily(TargetDeviceFamily)
    case packageDependency(PackageDependency)
  }

  /// A `<TargetDeviceFamily>` element, which specifies a device family that the
  /// package supports.
  struct TargetDeviceFamily: Hashable, Equatable, Codable {
    enum CodingKeys: String, CodingKey {
      case name = "Name"
      case minimumVersion = "MinVersion"
      case maximumVersionTested = "MaxVersionTested"
    }

    @Attribute var name: String
    @Attribute var minimumVersion: String
    @Attribute var maximumVersionTested: String

    /// Creates a new `TargetDeviceFamily` with the given properties.
    /// - Parameters:
    ///   - name: The name of the target device family.
    ///   - minimumVersion: The minimum required version of the target device
    ///     family.
    ///   - maximumVersionTested: The maximum version of the target device family
    ///     that the package has been tested on.
    init(name: String, minimumVersion: String, maximumVersionTested: String) {
      self._name = Attribute(name)
      self._minimumVersion = Attribute(minimumVersion)
      self._maximumVersionTested = Attribute(maximumVersionTested)
    }
  }

  /// A `<PackageDependency>` element, which specifies a dependency on another
  /// package.
  struct PackageDependency: Hashable, Equatable, Codable {
    enum CodingKeys: String, CodingKey {
      case name = "Name"
      case publisher = "Publisher"
      case minimumVersion = "MinVersion"
    }

    @Attribute var name: String
    @Attribute var publisher: String
    @Attribute var minimumVersion: String

    /// Creates a new `PackageDependency` with the given properties.
    /// - Parameters:
    ///   - name: The name of the package that this package depends on.
    ///   - publisher: The publisher of the package.
    ///   - minimumVersion: The minimum version of the package that this package
    ///     depends on.
    init(name: String, publisher: String, minimumVersion: String) {
      self._name = Attribute(name)
      self._publisher = Attribute(publisher)
      self._minimumVersion = Attribute(minimumVersion)
    }
  }

  /// The `<Capabilities>` element, which contains the capabilities that the
  /// package supports.
  struct Capabilities: Hashable, Equatable, Codable {
    enum CodingKeys: String, CodingKey {
      case capabilities = ""
    }

    @Element var capabilities: [SomeCapability]

    /// Creates a new `Capabilities` with the given capabilities.
    /// - Parameter capabilities: The list of capabilities.
    init(_ capabilities: [SomeCapability]) {
      self._capabilities = Element(capabilities)
    }
  }

  /// A single declared capability inside `<Capabilities>`.
  enum SomeCapability: Hashable, Equatable, Codable {
    enum CodingKeys: String, CodingKey, XMLChoiceCodingKey {
      case capability = "Capability"
      case rescapCapability = "rescap:Capability"
      case deviceCapability = "DeviceCapability"
    }
    enum CapabilityCodingKeys: String, CodingKey { case _0 = "" }
    enum RescapCapabilityCodingKeys: String, CodingKey { case _0 = "" }
    enum DeviceCapabilityCodingKeys: String, CodingKey { case _0 = "" }

    case capability(Capability)
    case rescapCapability(RescapCapability)
    case deviceCapability(DeviceCapability)
  }

  /// A `<Capability>` element, which specifies a capability that the package
  /// supports.
  struct Capability: Hashable, Equatable, Codable {
    enum CodingKeys: String, CodingKey {
      case name = "Name"
    }

    @Attribute var name: String

    /// Creates a new `Capability` with the given name.
    /// - Parameter name: The name of the capability.
    init(name: String) {
      self._name = Attribute(name)
    }
  }

  /// A `<rescap:Capability>` element, which specifies a capability that the
  /// package supports.
  struct RescapCapability: Hashable, Equatable, Codable {
    enum CodingKeys: String, CodingKey {
      case name = "Name"
    }

    @Attribute var name: String

    /// Creates a new `RescapCapability` with the given name.
    /// - Parameter name: The name of the capability.
    init(name: String) {
      self._name = Attribute(name)
    }
  }

  /// A `<DeviceCapability>` element, which specifies a device capability that
  /// the package supports.
  struct DeviceCapability: Hashable, Equatable, Codable {
    enum CodingKeys: String, CodingKey {
      case name = "Name"
    }

    @Attribute var name: String

    /// Creates a new `DeviceCapability` with the given name.
    /// - Parameter name: The name of the device capability.
    init(name: String) {
      self._name = Attribute(name)
    }
  }

  /// The `<Applications>` element, which contains one or more `<Application>`
  /// elements.
  struct Applications: Hashable, Equatable, Codable {
    enum CodingKeys: String, CodingKey {
      case applications = "Application"
    }

    var applications: [Application]

    /// Creates a new `Applications` with the given applications.
    init(_ applications: [Application]) {
      self.applications = applications
    }
  }

  /// An `<Application>` element, which represents an application within the
  /// package.
  struct Application: Hashable, Equatable, Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
      case id = "Id"
      case executable = "Executable"
      case entryPoint = "EntryPoint"
      case uapVisualElements = "uap:VisualElements"
      case extensions = "Extensions"
    }

    @Attribute var id: String
    @Attribute var executable: String
    @Attribute var entryPoint: String
    var uapVisualElements: UAPVisualElements?
    var extensions: [SomeApplicationExtension]

    /// Custom decoder to ensure that missing elements are decoded properly.
    /// - Parameter decoder: The decoder to decode from.
    /// - Throws: An error if decoding fails.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self._id = try container.decode(Attribute<String>.self, forKey: .id)
      self._executable = try container.decode(Attribute<String>.self, forKey: .executable)
      self._entryPoint = try container.decode(Attribute<String>.self, forKey: .entryPoint)
      self.uapVisualElements = try container.decodeIfPresent(
        Element<UAPVisualElements>.self,
        forKey: .uapVisualElements
      )?.wrappedValue
      self.extensions =
        try container.decodeIfPresent(
          Element<ApplicationExtensions>.self,
          forKey: .extensions
        )?.wrappedValue.extensions ?? []
    }

    /// Creates a new `Application` with the given properties.
    /// - Parameters:
    ///   - id: The ID of the application.
    ///   - executable: The path to the application's executable, relative to
    ///     the package root.
    ///   - entryPoint: The entry point of the application.
    ///   - uapVisualElements: The `<uap:VisualElements>` element of the
    ///     application.
    ///   - extensions: Any extensions that the application supports.
    init(
      id: String,
      executable: String,
      entryPoint: String,
      uapVisualElements: UAPVisualElements? = nil,
      extensions: [SomeApplicationExtension] = []
    ) {
      self._id = Attribute(id)
      self._executable = Attribute(executable)
      self._entryPoint = Attribute(entryPoint)
      self.uapVisualElements = uapVisualElements
      self.extensions = extensions
    }

    /// Custom encoder to ensure that empty elements are not encoded.
    /// - Parameter encoder: The encoder to encode to.
    /// - Throws: An error if encoding fails.
    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(_id, forKey: .id)
      try container.encode(_executable, forKey: .executable)
      try container.encode(_entryPoint, forKey: .entryPoint)
      try container.encodeIfPresent(
        uapVisualElements.map { Element($0) },
        forKey: .uapVisualElements
      )
      if !extensions.isEmpty {
        try container.encode(Element(ApplicationExtensions(extensions)), forKey: .extensions)
      }
    }
  }

  /// The `<uap:VisualElements>` element, which contains visual elements for an
  /// application, such as its display name and logos.
  struct UAPVisualElements: Hashable, Equatable, Codable {
    enum CodingKeys: String, CodingKey {
      case displayName = "DisplayName"
      case description = "Description"
      case backgroundColor = "BackgroundColor"
      case square150x150Logo = "Square150x150Logo"
      case square44x44Logo = "Square44x44Logo"
    }

    @Attribute var displayName: String
    @Attribute var description: String
    @Attribute var backgroundColor: String
    @Attribute var square150x150Logo: String
    @Attribute var square44x44Logo: String

    /// Creates a new `UAPVisualElements` with the given properties.
    /// - Parameters:
    ///   - displayName: The display name of the application.
    ///   - description: The description of the application.
    ///   - backgroundColor: The background color to use for the application, in
    ///     hex format.
    ///   - square150x150Logo: The path to the 150x150 logo for the application,
    ///     relative to the package root.
    ///   - square44x44Logo: The path to the 44x44 logo for the application,
    ///     relative to the package root.
    init(
      displayName: String,
      description: String,
      backgroundColor: String,
      square150x150Logo: String,
      square44x44Logo: String
    ) {
      self._displayName = Attribute(displayName)
      self._description = Attribute(description)
      self._backgroundColor = Attribute(backgroundColor)
      self._square150x150Logo = Attribute(square150x150Logo)
      self._square44x44Logo = Attribute(square44x44Logo)
    }
  }

  /// The `<Extensions>` element, which contains one or more extensions for an
  /// application, such as protocol handlers or full trust process declarations.
  struct ApplicationExtensions: Hashable, Equatable, Codable {
    enum CodingKeys: String, CodingKey {
      case extensions = ""
    }

    @Element var extensions: [SomeApplicationExtension]

    /// Creates a new `ApplicationExtensions` with the given extensions.
    /// - Parameter extensions: The list of extensions.
    init(_ extensions: [SomeApplicationExtension]) {
      self._extensions = Element(extensions)
    }
  }

  /// An `<Extension>` element, which represents an extension for an
  /// application.
  enum SomeApplicationExtension: Hashable, Equatable, Codable {
    enum CodingKeys: String, CodingKey, XMLChoiceCodingKey {
      case desktopExtension = "desktop:Extension"
      case uap3Extension = "uap3:Extension"
    }

    enum Uap3ExtensionCodingKeys: String, CodingKey { case _0 = "" }
    enum DesktopExtensionCodingKeys: String, CodingKey { case _0 = "" }

    case desktopExtension(SomeApplicationDesktopExtension)
    case uap3Extension(SomeApplicationUAP3Extension)
  }

  /// A `<desktop:Extension>` element, which represents a extension in the
  /// desktop namespace, such as a full trust process declaration.
  enum SomeApplicationDesktopExtension: Hashable, Equatable, Codable {
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

    case fullTrustProcess(ApplicationDesktopFullTrustProcess)

    /// Custom decoder to decode types based on the category attribute.
    /// - Parameter decoder: The decoder to decode from.
    /// - Throws: An error if the category is unknown or if decoding fails.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let category = try container.decode(
        Attribute<String>.self,
        forKey: .category
      ).wrappedValue
      switch category {
        case CodingKeys.fullTrustProcess.category:
          let executable = try container.decodeIfPresent(
            Attribute<String>.self,
            forKey: .executable
          )?.wrappedValue
          // In the future, <desktop:ParameterGroup> elements may be added.
          self = .fullTrustProcess(
            ApplicationDesktopFullTrustProcess(
              executable: executable
            )
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

    /// Custom encoder to encode types along with the appropriate category
    /// attribute.
    /// - Parameter encoder: The encoder to encode to.
    /// - Throws: An error if encoding fails.
    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      switch self {
        case .fullTrustProcess(let process):
          try container.encodeIfPresent(
            Attribute(CodingKeys.fullTrustProcess.category),
            forKey: .category
          )
          if let executable = process.executable {
            try container.encode(
              Attribute(executable),
              forKey: .executable
            )
          }
      }
    }
  }

  /// The `<desktop:FullTrustProcess>` element, which represents a full trust
  /// process declaration in the desktop namespace.
  ///
  /// When this is the only content of a `<desktop:Extension>` (its `Executable`
  /// is encoded as an attribute on the parent `<desktop:Extension>` element),
  /// the `<desktop:FullTrustProcess>` element should not be encoded at all.
  /// The element `<desktop:FullTrustProcess>` is only required when there are
  /// `<desktop:ParameterGroup>` children to encode, which isn't supported yet.
  ///
  /// todo: support `<desktop:ParameterGroup>`.
  struct ApplicationDesktopFullTrustProcess: Hashable, Equatable, Codable {
    enum CodingKeys: String, CodingKey {
      case executable = ""
    }

    var executable: String?

    /// Creates a new `ApplicationDesktopFullTrustProcess` with the given executable.
    /// - Parameter executable: The path to the executable for the full trust
    ///   process, relative to the package root.
    init(executable: String?) {
      self.executable = executable
    }
  }

  /// An `<uap3:Extension>` element, which represents an extension in the uap3
  /// namespace, such as a protocol handler declaration.
  enum SomeApplicationUAP3Extension: Hashable, Equatable, Codable {
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

    case uap3Protocol(ApplicationUAP3Protocol)

    /// Custom decoder to decode types based on the category attribute.
    /// - Parameter decoder: The decoder to decode from.
    /// - Throws: An error if the category is unknown or if decoding fails.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let category = try container.decode(
        Attribute<String>.self,
        forKey: .category
      ).wrappedValue
      switch category {
        case CodingKeys.uap3Protocol.category:
          self = .uap3Protocol(
            try container.decode(
              Element<ApplicationUAP3Protocol>.self,
              forKey: .uap3Protocol
            ).wrappedValue
          )
        default:
          throw DecodingError.dataCorrupted(
            DecodingError.Context(
              codingPath: decoder.codingPath,
              debugDescription: "Unknown Category '\(category)' on <uap3:Extension>"
            )
          )
      }
    }

    /// Custom encoder to encode types along with the appropriate category
    /// - Parameter encoder: The encoder to encode to.
    /// - Throws: An error if encoding fails.
    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      switch self {
        case .uap3Protocol(let protocolData):
          try container.encodeIfPresent(
            Attribute(CodingKeys.uap3Protocol.category),
            forKey: .category
          )
          try container.encode(
            Element(protocolData),
            forKey: .uap3Protocol
          )
      }
    }
  }

  /// A `<uap3:Protocol>` element, which represents a protocol handler
  /// declaration.
  struct ApplicationUAP3Protocol: Hashable, Equatable, Codable {
    enum CodingKeys: String, CodingKey {
      case name = "Name"
      case displayName = "uap:DisplayName"
      case logo = "uap:Logo"
    }

    @Attribute var name: String
    var displayName: String?
    var logo: String?

    /// Custom decoder to ensure that optional elements are decoded properly.
    /// - Parameter decoder: The decoder to decode from.
    /// - Throws: An error if decoding fails.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self._name = try container.decode(Attribute<String>.self, forKey: .name)
      self.displayName = try container.decodeIfPresent(
        Element<String>.self,
        forKey: .displayName
      )?.wrappedValue
      self.logo = try container.decodeIfPresent(
        Element<String>.self,
        forKey: .logo
      )?.wrappedValue
    }

    /// Creates a new `ApplicationUAP3Protocol` with the given properties.
    /// - Parameters:
    ///   - name: The name of the protocol that this extension handles.
    ///   - displayName: The display name for this protocol.
    ///   - logo: The path to the logo for this protocol, relative to the
    ///     package
    init(name: String, displayName: String?, logo: String?) {
      self._name = Attribute(name)
      self.displayName = displayName
      self.logo = logo
    }

    /// Custom encoder to ensure that optional elements are not encoded when
    /// nil.
    /// - Parameter encoder: The encoder to encode to.
    /// - Throws: An error if encoding fails.
    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(_name, forKey: .name)
      try container.encodeIfPresent(
        displayName.map { Element($0) },
        forKey: .displayName
      )
      try container.encodeIfPresent(
        logo.map { Element($0) },
        forKey: .logo
      )
    }
  }

  /// Encodes an `Package` manifest to XML data.
  /// - Parameters:
  ///   - manifest: The manifest to encode.
  ///   - disablingRootAttributesForTesting: If true, the root attributes will
  ///     not be included in the encoded. This is required because
  ///     rootAttributes have no guaranteed order and are essentially in random
  ///     order. See: https://github.com/CoreOffice/XMLCoder/issues/297
  /// - Returns: The encoded XML data.
  /// - Throws: An error if encoding fails.
  static func encodeManifest(
    _ manifest: Package,
    disablingRootAttributesForTesting: Bool = false
  ) throws -> Data {
    let encoder = XMLEncoder()
    encoder.outputFormatting = [.prettyPrinted]

    let rootAttributes = [
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
    ]

    return try encoder.encode(
      manifest,
      withRootKey: "Package",
      rootAttributes: disablingRootAttributesForTesting ? [:] : rootAttributes,
      header: XMLHeader(version: 1.0, encoding: "utf-8")
    )
  }
}
