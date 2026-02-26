import Foundation

/// The parsed output of an executed `Package.swift` file.
struct PackageManifest: Sendable, Decodable {
  struct VersionedPlatform: Sendable, Decodable {
    var name: String
    var version: String
  }

  struct Product: Sendable, Decodable {
    var name: String
    var type: ProductType
    var targets: [String]
  }

  struct Target: Sendable, Decodable {
    var name: String
    var type: TargetType
    var path: String
    var targetDependencies: [String]?
    var productDependencies: [String]?

    enum CodingKeys: String, CodingKey {
      case name
      case type
      case path
      case targetDependencies = "target_dependencies"
      case productDependencies = "product_dependencies"
    }
  }

  enum TargetType: Sendable, Decodable, Hashable {
    case library
    case executable
    case systemTarget
    case test
    case plugin
    case macro
    case snippet
    case other(String)

    init(from decoder: any Decoder) throws {
      do {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
          case "library": self = .library
          case "executable": self = .executable
          case "system-target": self = .systemTarget
          case "test": self = .test
          case "plugin": self = .plugin
          case "macro": self = .macro
          case "snippet": self = .snippet
          case let other: self = .other(other)
        }
      } catch {
        // We want to fail as gracefully as possible when the JSON format
        // changes in future.
        log.warning(
          """
          Failed to parse Swift target type, skipping target. Please open an \
          issue at \(SwiftBundler.newIssueURL). Cause: \
          \(error.localizedDescription)
          """
        )
        self = .other("<not_a_string>")
      }
    }
  }

  enum ProductType: Sendable, Decodable, Hashable {
    case executable
    case library(String)
    case plugin
    case macro
    case snippet
    case unknown

    enum CodingKeys: String, CodingKey {
      case executable
      case library
      case plugin
      case macro
      case snippet
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      if container.contains(.executable) {
        self = .executable
      } else if container.contains(.plugin) {
        self = .plugin
      } else if container.contains(.macro) {
        self = .macro
      } else if container.contains(.snippet) {
        self = .snippet
      } else if container.contains(.library) {
        let elements = try container.decode([String].self, forKey: .library)
        guard elements.count == 1 else {
          throw DecodingError.dataCorruptedError(
            forKey: .library,
            in: container,
            debugDescription: "Expected array of length 1"
          )
        }
        let linkingMode = elements[0]
        self = .library(linkingMode)
      } else {
        self = .unknown
      }
    }
  }

  struct PackageDependency: Sendable, Codable {
    var identity: String
    var location: Location

    enum CodingKeys: String, CodingKey {
      case identity
      case path
      case type
      case url
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      identity = try container.decode(String.self, forKey: .identity)

      let type = try container.decode(LocationType.self, forKey: .type)
      switch type {
        case .fileSystem:
          let path = try container.decode(String.self, forKey: .path)
          location = .fileSystem(path: URL(fileURLWithPath: path))
        case .sourceControl:
          let url = try container.decode(URL.self, forKey: .url)
          location = .sourceControl(url: url)
      }
    }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(identity, forKey: .identity)
      switch location {
        case .fileSystem(let path):
          try container.encode(LocationType.fileSystem, forKey: .type)
          try container.encode(path.path, forKey: .path)
        case .sourceControl(let url):
          try container.encode(LocationType.sourceControl, forKey: .type)
          try container.encode(url, forKey: .url)
      }
    }

    /// Only used in our Decodable implementation
    enum LocationType: String, Codable {
      case fileSystem
      case sourceControl
    }

    enum Location: Sendable {
      case fileSystem(path: URL)
      case sourceControl(url: URL)

      var isRemote: Bool {
        switch self {
          case .fileSystem: false
          case .sourceControl: true
        }
      }
    }

    /// Gets the path to the given dependency's local checkout. If the dependency
    /// is a local package dependency, then this returns the path to the
    /// dependency's source on disk.
    func localCheckout(packageDirectory: URL, checkoutsDirectory: URL) -> URL {
      switch location {
        case .fileSystem(let path):
          path
        case .sourceControl:
          checkoutsDirectory / identity
      }
    }
  }

  var name: String
  var dependencies: [PackageDependency]
  var platforms: [VersionedPlatform]?
  var products: [Product]
  var targets: [Target]

  func platformVersion(for platform: ApplePlatform) -> String? {
    if let platformVersion = platforms?.first(where: { manifestPlatform in
      platform.manifestPlatformName == manifestPlatform.name
    })?.version {
      if platform == .macCatalyst && platformVersion == "13.0" {
        "13.1"
      } else {
        platformVersion
      }
    } else {
      nil
    }
  }
}
