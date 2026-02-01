import Foundation
import Parsing

/// A utility for creating the contents of plist files.
enum PlistCreator {
  /// Creates an app's `Info.plist` file.
  /// - Parameters:
  ///   - file: The URL of the file to create.
  ///   - appName: The name of the app.
  ///   - configuration: The app's configuration.
  ///   - platform: The platform the app is for.
  ///   - platformVersion: The minimum platform version that the app should
  ///     run on.
  static func createAppInfoPlist(
    at file: URL,
    appName: String,
    configuration: AppConfiguration.Flat,
    platform: Platform,
    platformVersion: String,
    partialInfoPlist: [String: Any]? = nil
  ) throws(Error) {
    let contents = try createAppInfoPlistContents(
      appName: appName,
      configuration: configuration,
      platform: platform,
      platformVersion: platformVersion,
      partialInfoPlist: partialInfoPlist
    )

    do {
      try contents.write(to: file)
    } catch {
      throw Error(.failedToWriteAppInfoPlist(file: file), cause: error)
    }
  }

  /// Creates the `Info.plist` file for a resource bundle.
  /// - Parameters:
  ///   - file: The URL of the file to create.
  ///   - bundleName: The bundle's name.
  ///   - minimumOSVersion: The minimum OS version that the resource bundle
  ///     should work on.
  ///   - platform: The platform the bundle is for.
  ///   - platformVersion: The minimum platform version that the app should
  ///     run on.
  static func createResourceBundleInfoPlist(
    at file: URL,
    bundleName: String,
    platform: Platform,
    platformVersion: String
  ) throws(Error) {
    let contents = try createResourceBundleInfoPlistContents(
      bundleName: bundleName,
      platform: platform,
      platformVersion: platformVersion
    )

    do {
      try contents.write(to: file)
    } catch {
      throw Error(
        .failedToWriteResourceBundleInfoPlist(bundle: bundleName, file: file),
        cause: error
      )
    }
  }

  /// Creates the contents of an app's `Info.plist` file.
  /// - Parameters:
  ///   - appName: The app's name.
  ///   - configuration: The app's configuration.
  ///   - platform: The platform the app is for.
  ///   - platformVersion: The minimum platform version that the app should
  ///     run on.
  /// - Returns: The generated contents for the `Info.plist` file.
  static func createAppInfoPlistContents(
    appName: String,
    configuration: AppConfiguration.Flat,
    platform: Platform,
    platformVersion: String,
    partialInfoPlist: [String: Any]? = nil
  ) throws(Error) -> Data {
    var entries: [String: Any?] = [
      "CFBundleDevelopmentRegion": "en",
      "CFBundleExecutable": appName,
      "CFBundleIconFile": "AppIcon",
      "CFBundleIconName": "AppIcon",
      "CFBundleIdentifier": configuration.identifier,
      "CFBundleInfoDictionaryVersion": "6.0",
      "CFBundleName": appName,
      "CFBundlePackageType": "APPL",
      "CFBundleShortVersionString": configuration.version,
      "CFBundleVersion": configuration.version,
      "LSApplicationCategoryType": configuration.category,
    ]

    switch platform {
      case .macOS, .macCatalyst:
        entries["LSMinimumSystemVersion"] = platformVersion
        entries["CFBundleSupportedPlatforms"] = ["MacOSX"]

        if platform == .macCatalyst {
          switch configuration.catalystInterfaceIdiom {
            case .ipad:
              entries["UIDeviceFamily"] = [2]
            case .mac:
              entries["UIDeviceFamily"] = [6]
          }
        }
      case .iOS, .iOSSimulator:
        entries["MinimumOSVersion"] = platformVersion
        entries["CFBundleSupportedPlatforms"] = ["iPhoneOS"]
        entries["UILaunchScreen"] = [String: Any]()
        entries["UIDeviceFamily"] = [1, 2]
      case .tvOS, .tvOSSimulator:
        entries["MinimumOSVersion"] = platformVersion
        entries["CFBundleSupportedPlatforms"] = ["AppleTVOS"]
      case .visionOS, .visionOSSimulator:
        // using Apple's HelloWorld visionOS demo as a reference
        // ref: https://developer.apple.com/documentation/visionos/world
        entries["MinimumOSVersion"] = platformVersion
        entries["CFBundleSupportedPlatforms"] = ["XROS"]
        entries["UIApplicationSceneManifest"] = [
          "UIApplicationSupportsMultipleScenes": true,
          "UISceneConfigurations": [String: Any](),
        ]
        entries["UINativeSizeClass"] = 1
        entries["UIDeviceFamily"] = [7]
      case .linux, .windows:
        break
    }

    if !configuration.urlSchemes.isEmpty {
      entries["CFBundleURLTypes"] = [
        [
          "CFBundleTypeRole": "Viewer",
          "CFBundleURLSchemes": configuration.urlSchemes,
        ]
      ]
    }

    if let partialInfoPlist {
      for (key, value) in partialInfoPlist {
        entries[key] = value
      }
    }

    for (key, value) in configuration.plist {
      entries[key] = value.value
    }

    return try Self.serialize(entries.compactMapValues { $0 })
  }

  /// Creates the contents of a resource bundle's `Info.plist` file.
  /// - Parameters:
  ///   - bundleName: The bundle's name.
  ///   - platform: The platform the bundle is for.
  ///   - platformVersion: The minimum platform version that the app should run on.
  /// - Returns: The generated contents for the `Info.plist` file.
  static func createResourceBundleInfoPlistContents(
    bundleName: String,
    platform: Platform,
    platformVersion: String
  ) throws(Error) -> Data {
    let bundleIdentifier = bundleName.replacingOccurrences(of: "_", with: "-") + "-resources"
    var entries: [String: Any?] = [
      "CFBundleIdentifier": bundleIdentifier,
      "CFBundleInfoDictionaryVersion": "6.0",
      "CFBundleName": bundleName,
      "CFBundlePackageType": "BNDL",
    ]

    // TODO: Clean this up, there's a lot of repetition. Also it could be reused by
    //   `createAppInfoPlistContents` which contains all these key-value pairs and just
    //   a few extra ones.
    switch platform {
      case .macOS, .macCatalyst:
        entries["LSMinimumSystemVersion"] = platformVersion
        entries["CFBundleSupportedPlatforms"] = ["MacOSX"]
      case .iOS, .iOSSimulator:
        // TODO: Make the produced Info.plist for iOS identical to Xcode's
        entries["MinimumOSVersion"] = platformVersion
        entries["CFBundleSupportedPlatforms"] = ["iPhoneOS"]
      case .tvOS, .tvOSSimulator:
        entries["MinimumOSVersion"] = platformVersion
        entries["CFBundleSupportedPlatforms"] = ["AppleTVOS"]
      case .visionOS, .visionOSSimulator:
        // TODO: Make the produced Info.plist for visionOS identical to Xcode's
        entries["MinimumOSVersion"] = platformVersion
        entries["CFBundleSupportedPlatforms"] = ["XROS"]
      case .linux, .windows:
        break
    }

    return try Self.serialize(entries.compactMapValues { $0 })
  }

  /// Serializes a plist dictionary into an `xml` format.
  /// - Parameter entries: The dictionary of entries to serialize.
  /// - Returns: The plist dictionary serialized as a string containing xml.
  static func serialize(_ entries: [String: Any]) throws(Error) -> Data {
    try Error.catch(withMessage: .serializationFailed) {
      try PropertyListSerialization.data(
        fromPropertyList: entries,
        format: .xml,
        options: 0
      )
    }
  }
}
