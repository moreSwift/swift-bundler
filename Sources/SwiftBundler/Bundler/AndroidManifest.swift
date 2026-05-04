import Foundation
import XMLCoder

/// The contents of an AndroidManifest.xml file.
struct AndroidManifest: Codable {
  @Element var application: Application
  @Element var permissions: [Permission]

  enum CodingKeys: String, CodingKey {
    case application
    case permissions = "uses-permission"
  }

  init(_ application: Application, permissions: [AndroidManifest.Permission]) {
    _application = Element(application)
    _permissions = Element(permissions)
  }

  struct Application: Codable {
    @Attribute var allowBackup: Bool?
    @Attribute var icon: String?
    @Attribute var label: String?
    @Attribute var theme: String?
    @Attribute var targetAPI: Int?

    @Element var activities: [Activity]

    enum CodingKeys: String, CodingKey {
      case allowBackup = "android:allowBackup"
      case icon = "android:icon"
      case label = "android:label"
      case theme = "android:theme"
      case targetAPI = "tools:targetApi"
      case activities = "activity"
    }

    init(
      allowBackup: Bool? = nil,
      icon: String? = nil,
      label: String? = nil,
      theme: String? = nil,
      targetAPI: Int? = nil,
      activities: [AndroidManifest.Activity]
    ) {
      _allowBackup = Attribute(allowBackup)
      _icon = Attribute(icon)
      _label = Attribute(label)
      _theme = Attribute(theme)
      _targetAPI = Attribute(targetAPI)
      _activities = Element(activities)
    }
  }

  struct Activity: Codable {
    @Attribute var name: String?
    @Attribute var exported: Bool?

    @Element var intentFilters: [IntentFilter]

    enum CodingKeys: String, CodingKey {
      case name = "android:name"
      case exported = "android:exported"
      case intentFilters = "intent-filter"
    }

    init(
      name: String? = nil,
      exported: Bool? = nil,
      intentFilters: [AndroidManifest.IntentFilter]
    ) {
      _name = Attribute(name)
      _exported = Attribute(exported)
      _intentFilters = Element(intentFilters)
    }
  }

  struct IntentFilter: Codable {
    @Element var action: Action
    @Element var category: Category?

    init(
      action: Action,
      category: Category? = nil
    ) {
      _action = Element(action)
      _category = Element(category)
    }

    struct Action: Codable {
      @Attribute var name: String?

      enum CodingKeys: String, CodingKey {
        case name = "android:name"
      }

      init(name: String? = nil) {
        _name = Attribute(name)
      }
    }

    struct Category: Codable {
      @Attribute var name: String?

      enum CodingKeys: String, CodingKey {
        case name = "android:name"
      }

      init(name: String? = nil) {
        _name = Attribute(name)
      }
    }
  }

  struct Permission: Codable {
    @Attribute var name: String
    @Attribute var maxSDKVersion: Int?

    enum CodingKeys: String, CodingKey {
      case name = "android:name"
      case maxSDKVersion = "android:maxSdkVersion"
    }

    init(name: String, maxSDKVersion: Int? = nil) {
      _name = Attribute(name)
      _maxSDKVersion = Attribute(maxSDKVersion)
    }
  }

  /// Encode the manifest to XML.
  func encode() throws -> Data {
    let encoder = XMLEncoder()
    encoder.prettyPrintIndentation = .spaces(4)
    encoder.outputFormatting = .prettyPrinted
    return try encoder.encode(
      self,
      withRootKey: "manifest",
      rootAttributes: [
        "xmlns:android": "http://schemas.android.com/apk/res/android",
        "xmlns:tools": "http://schemas.android.com/tools",
      ],
      header: XMLHeader(version: 1, encoding: "utf-8")
    )
  }
}
