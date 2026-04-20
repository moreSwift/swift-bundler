import XMLCoder

extension MSIBundler {
  /// A representation for WXS files with the parts that Swift Bundler needs.
  /// This isn't intended to be used to parse or produce arbitrary WXS files.
  /// Notably we have a lot of non-nullable properties that in reality are
  /// nullable from WiX's point of view.
  struct WXSFile: Encodable, Sendable {
    @Attribute var xmlns: String
    @Element var package: Package

    init(xmlns: String, package: MSIBundler.WXSFile.Package) {
      self._xmlns = Attribute(xmlns)
      self._package = Element(package)
    }

    enum CodingKeys: String, CodingKey {
      case xmlns
      case package = "Package"
    }

    struct Package: Codable, Sendable {
      @Attribute var language: Language
      @Attribute var manufacturer: String
      @Attribute var name: String
      @Attribute var upgradeCode: String
      @Attribute var version: String

      @Element var majorUpgrade: MajorUpgrade
      @Element var mediaTemplate: MediaTemplate

      @Element var icons: [Icon]
      @Element var properties: [Property]

      @Element var standardDirectories: [StandardDirectory]
      @Element var componentGroups: [ComponentGroup]

      @Element var customActions: [CustomAction]
      @Element var installUISequences: [InstallUISequence]
      @Element var installExecuteSequences: [InstallExecuteSequence]

      var additionalAttributes: [String: String]
      var additionalChildren: [WXSValue]

      struct CodingKeys: OpenCodingKey {
        static let language = Self("Language")
        static let manufacturer = Self("Manufacturer")
        static let name = Self("Name")
        static let upgradeCode = Self("UpgradeCode")
        static let version = Self("Version")
        static let majorUpgrade = Self("MajorUpgrade")
        static let mediaTemplate = Self("MediaTemplate")
        static let icons = Self("Icon")
        static let properties = Self("Property")
        static let standardDirectories = Self("StandardDirectory")
        static let componentGroups = Self("ComponentGroup")
        static let customActions = Self("CustomAction")
        static let installUISequences = Self("InstallUISequence")
        static let installExecuteSequences = Self("InstallExecuteSequence")

        let stringValue: String
        var intValue: Int? { nil }

        init?(intValue: Int) {
          return nil
        }

        init(_ stringValue: String) {
          self.stringValue = stringValue
        }
      }

      enum Language: String, Codable {
        case english = "1033"
      }

      init(
        language: Language,
        manufacturer: String,
        name: String,
        upgradeCode: String,
        version: String,
        majorUpgrade: MajorUpgrade,
        mediaTemplate: MediaTemplate,
        icons: [Icon] = [],
        properties: [Property] = [],
        standardDirectories: [StandardDirectory] = [],
        componentGroups: [ComponentGroup] = [],
        customActions: [CustomAction] = [],
        installUISequences: [InstallUISequence] = [],
        installExecuteSequences: [InstallExecuteSequence] = [],
        additionalAttributes: [String: String] = [:],
        additionalChildren: [WXSValue] = []
      ) {
        self._language = Attribute(language)
        self._manufacturer = Attribute(manufacturer)
        self._name = Attribute(name)
        self._upgradeCode = Attribute(upgradeCode)
        self._version = Attribute(version)
        self._majorUpgrade = Element(majorUpgrade)
        self._mediaTemplate = Element(mediaTemplate)
        self._icons = Element(icons)
        self._properties = Element(properties)
        self._standardDirectories = Element(standardDirectories)
        self._componentGroups = Element(componentGroups)
        self._customActions = Element(customActions)
        self._installUISequences = Element(installUISequences)
        self._installExecuteSequences = Element(installExecuteSequences)
        self.additionalAttributes = additionalAttributes
        self.additionalChildren = additionalChildren
      }

      func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(_language, forKey: .language)
        try container.encode(_manufacturer, forKey: .manufacturer)
        try container.encode(_name, forKey: .name)
        try container.encode(_upgradeCode, forKey: .upgradeCode)
        try container.encode(_version, forKey: .version)
        try container.encode(_majorUpgrade, forKey: .majorUpgrade)
        try container.encode(
          _mediaTemplate,
          forKey: .mediaTemplate
        )
        try container.encode(_icons, forKey: .icons)
        try container.encode(_properties, forKey: .properties)
        try container.encode(
          _standardDirectories,
          forKey: .standardDirectories
        )
        try container.encode(
          _componentGroups,
          forKey: .componentGroups
        )
        try container.encode(
          _customActions,
          forKey: .customActions
        )
        try container.encode(
          _installUISequences,
          forKey: .installUISequences
        )
        try container.encode(
          _installExecuteSequences,
          forKey: .installExecuteSequences
        )

        let additions = WXSValueXML(value: WXSValue(
          tag: "",
          attributes: additionalAttributes,
          children: additionalChildren
        ))
        try additions.encode(intoContainer: &container)
      }

      init(from decoder: any Decoder) throws {
        fatalError(
          """
          Decodable not implemented for WXSFile.Product; conformance exists to \
          satisfy XMLCoder.Element requirements
          """
        )
      }
    }

    struct MajorUpgrade: Codable {
      @Attribute var allowSameVersionUpgrades: YesOrNo
      @Attribute var downgradeErrorMessage: String

      enum CodingKeys: String, CodingKey {
        case allowSameVersionUpgrades = "AllowSameVersionUpgrades"
        case downgradeErrorMessage = "DowngradeErrorMessage"
      }

      init(
        allowSameVersionUpgrades: YesOrNo,
        downgradeErrorMessage: String
      ) {
        self._allowSameVersionUpgrades = Attribute(allowSameVersionUpgrades)
        self._downgradeErrorMessage = Attribute(downgradeErrorMessage)
      }
    }

    struct MediaTemplate: Codable {
      @Attribute var embedCab: YesOrNo

      enum CodingKeys: String, CodingKey {
        case embedCab = "EmbedCab"
      }

      init(embedCab: MSIBundler.WXSFile.YesOrNo) {
        self._embedCab = Attribute(embedCab)
      }
    }

    struct Icon: Codable {
      @Attribute var id: String
      @Attribute var sourceFile: String

      enum CodingKeys: String, CodingKey {
        case id = "Id"
        case sourceFile = "SourceFile"
      }

      init(id: String, sourceFile: String) {
        self._id = Attribute(id)
        self._sourceFile = Attribute(sourceFile)
      }
    }

    struct Property: Codable {
      @Attribute var id: String
      @Attribute var value: String

      enum CodingKeys: String, CodingKey {
        case id = "Id"
        case value = "Value"
      }

      init(id: String, value: String) {
        self._id = Attribute(id)
        self._value = Attribute(value)
      }
    }

    struct StandardDirectory: Codable, Sendable {
      @Attribute var id: String
      @Element var directories: [Directory]

      enum CodingKeys: String, CodingKey {
        case id = "Id"
        case directories = "Directory"
      }

      init(id: String, directories: [Directory]) {
        self._id = Attribute(id)
        self._directories = Element(directories)
      }
    }

    struct Directory: Codable, Sendable {
      @Attribute var id: String?
      @Attribute var name: String
      @Element var directories: [Directory]
      @Element var files: [File]

      enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case directories = "Directory"
        case files = "File"
      }

      init(
        id: String? = nil,
        name: String,
        directories: [Directory] = [],
        files: [File] = []
      ) {
        self._id = Attribute(id)
        self._name = Attribute(name)
        self._directories = Element(directories)
        self._files = Element(files)
      }

      func renamed(to newName: String) -> Self {
        var directory = self
        directory.name = newName
        return directory
      }
    }

    struct ComponentGroup: Codable, Sendable {
      @Attribute var id: String
      @Attribute var directory: String
      @Element var components: [Component]

      enum CodingKeys: String, CodingKey {
        case id = "Id"
        case directory = "Directory"
        case components = "Component"
      }

      init(id: String, directory: String, components: [Component]) {
        self._id = Attribute(id)
        self._directory = Attribute(directory)
        self._components = Element(components)
      }
    }

    struct Component: Codable, Sendable {
      @Attribute var id: String
      @Element var files: [File]
      @Element var shortcuts: [Shortcut]
      @Element var folderRemovals: [RemoveFolder]
      @Element var registryValues: [RegistryValue]

      enum CodingKeys: String, CodingKey {
        case id = "Id"
        case files = "File"
        case shortcuts = "Shortcut"
        case folderRemovals = "RemoveFolder"
        case registryValues = "RegistryValue"
      }

      init(
        id: String,
        files: [File] = [],
        shortcuts: [Shortcut] = [],
        folderRemovals: [RemoveFolder] = [],
        registryValues: [RegistryValue] = []
      ) {
        self._id = Attribute(id)
        self._files = Element(files)
        self._shortcuts = Element(shortcuts)
        self._folderRemovals = Element(folderRemovals)
        self._registryValues = Element(registryValues)
      }
    }

    struct RemoveFolder: Codable, Sendable {
      @Attribute var id: String
      @Attribute var directory: String?
      @Attribute var on: String

      enum CodingKeys: String, CodingKey {
        case id = "Id"
        case directory = "Directory"
        case on = "On"
      }

      init(id: String, directory: String? = nil, on: String) {
        self._id = Attribute(id)
        self._directory = Attribute(directory)
        self._on = Attribute(on)
      }
    }

    struct File: Codable, Sendable {
      @Attribute var id: String?
      @Attribute var source: String

      enum CodingKeys: String, CodingKey {
        case id = "Id"
        case source = "Source"
      }

      init(id: String? = nil, source: String) {
        self._id = Attribute(id)
        self._source = Attribute(source)
      }
    }

    struct Shortcut: Codable, Sendable {
      @Attribute var id: String
      @Attribute var directory: String
      @Attribute var advertise: YesOrNo
      @Attribute var name: String
      @Attribute var description: String
      @Attribute var target: String
      @Attribute var workingDirectory: String?
      @Attribute var arguments: String?

      enum CodingKeys: String, CodingKey {
        case id = "Id"
        case directory = "Directory"
        case advertise = "Advertise"
        case name = "Name"
        case description = "Description"
        case target = "Target"
        case workingDirectory = "WorkingDirectory"
        case arguments = "Arguments"
      }

      init(
        id: String,
        directory: String,
        advertise: MSIBundler.WXSFile.YesOrNo,
        name: String,
        description: String,
        target: String,
        workingDirectory: String? = nil,
        arguments: String? = nil
      ) {
        self._id = Attribute(id)
        self._directory = Attribute(directory)
        self._advertise = Attribute(advertise)
        self._name = Attribute(name)
        self._description = Attribute(description)
        self._target = Attribute(target)
        self._workingDirectory = Attribute(workingDirectory)
        self._arguments = Attribute(arguments)
      }
    }

    struct RegistryValue: Codable, Sendable {
      @Attribute var root: String
      @Attribute var key: String
      @Attribute var name: String
      @Attribute var type: String
      @Attribute var value: String
      @Attribute var keyPath: YesOrNo

      enum CodingKeys: String, CodingKey {
        case root = "Root"
        case key = "Key"
        case name = "Name"
        case type = "Type"
        case value = "Value"
        case keyPath = "KeyPath"
      }

      init(
        root: String,
        key: String,
        name: String,
        type: String,
        value: String,
        keyPath: YesOrNo
      ) {
        self._root = Attribute(root)
        self._key = Attribute(key)
        self._name = Attribute(name)
        self._type = Attribute(type)
        self._value = Attribute(value)
        self._keyPath = Attribute(keyPath)
      }
    }

    enum YesOrNo: String, Codable, Sendable {
      case yes
      case no
    }

    struct CustomAction: Codable, Sendable {
      @Attribute var id: String
      @Attribute var property: String?
      @Attribute var value: String?
      @Attribute var execute: Scheduling
      @Attribute var impersonate: YesOrNo?
      @Attribute var `return`: Return?
      @Attribute var directory: String?
      @Attribute var exeCommand: String?

      init(
        id: String,
        property: String? = nil,
        value: String? = nil,
        execute: Scheduling,
        impersonate: YesOrNo? = nil,
        return: Return? = nil,
        directory: String? = nil,
        exeCommand: String? = nil
      ) {
        self._id = Attribute(id)
        self._property = Attribute(property)
        self._value = Attribute(value)
        self._execute = Attribute(execute)
        self._impersonate = Attribute(impersonate)
        self._return = Attribute(`return`)
        self._directory = Attribute(directory)
        self._exeCommand = Attribute(exeCommand)
      }

      enum Return: String, Codable {
        case asyncNoWait
        case asyncWait
        case check
        case ignore
      }

      enum Scheduling: String, Codable {
        case commit
        case deferred
        case firstSequence
        case immediate
        case oncePerProcess
        case rollback
        case secondSequence
      }

      enum CodingKeys: String, CodingKey {
        case id = "Id"
        case property = "Property"
        case value = "Value"
        case execute = "Execute"
        case impersonate = "Impersonate"
        case `return` = "Return"
        case directory = "Directory"
        case exeCommand = "ExeCommand"
      }
    }

    typealias InstallUISequence = InstallSequence
    typealias InstallExecuteSequence = InstallSequence

    /// Used for both InstallExecuteSequence and InstallUISequence because for
    /// our current purposes they are identical.
    struct InstallSequence: Codable, Sendable {
      @Element var custom: Custom

      init(custom: Custom) {
        self._custom = Element(custom)
      }

      enum CodingKeys: String, CodingKey {
        case custom = "Custom"
      }

      struct Custom: Codable {
        @Attribute var action: String
        @Attribute var after: String

        enum CodingKeys: String, CodingKey {
          case action = "Action"
          case after = "After"
        }

        init(action: String, after: String) {
          self._action = Attribute(action)
          self._after = Attribute(after)
        }
      }
    }
  }
}
