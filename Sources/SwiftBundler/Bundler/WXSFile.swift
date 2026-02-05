import XMLCoder
import Version

extension MSIBundler {
  struct WXSFile: Codable {
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

    struct Package: Codable {
      @Attribute var language: Language
      @Attribute var manufacturer: String
      @Attribute var name: String
      @Attribute var upgradeCode: String
      @Attribute var version: Version

      @Element var majorUpgrade: MajorUpgrade
      @Element var mediaTemplate: MediaTemplate

      @Element var icons: [Icon]
      @Element var properties: [Property]

      @Element var standardDirectories: [StandardDirectory]
      @Element var componentGroups: [ComponentGroup]

      enum CodingKeys: String, CodingKey {
        case language = "Language"
        case manufacturer = "Manufacturer"
        case name = "Name"
        case upgradeCode = "UpgradeCode"
        case version = "Version"
        case majorUpgrade = "MajorUpgrade"
        case mediaTemplate = "MediaTemplate"
        case icons = "Icon"
        case properties = "Property"
        case standardDirectories = "StandardDirectory"
        case componentGroups = "ComponentGroup"
      }

      enum Language: String, Codable {
        case english = "1033"
      }

      init(
        language: Language,
        manufacturer: String,
        name: String,
        upgradeCode: String,
        version: Version,
        majorUpgrade: MajorUpgrade,
        mediaTemplate: MediaTemplate,
        icons: [Icon] = [],
        properties: [Property] = [],
        standardDirectories: [StandardDirectory] = [],
        componentGroups: [ComponentGroup] = []
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
      }
    }

    struct MajorUpgrade: Codable {
      @Attribute var downgradeErrorMessage: String

      enum CodingKeys: String, CodingKey {
        case downgradeErrorMessage = "DowngradeErrorMessage"
      }

      init(downgradeErrorMessage: String) {
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

    struct StandardDirectory: Codable {
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

    struct Directory: Codable {
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

    struct ComponentGroup: Codable {
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

    struct Component: Codable {
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

    struct RemoveFolder: Codable {
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

    struct File: Codable {
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

    struct Shortcut: Codable {
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

    struct RegistryValue: Codable {
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

    enum YesOrNo: String, Codable {
      case yes
      case no
    }
  }
}
