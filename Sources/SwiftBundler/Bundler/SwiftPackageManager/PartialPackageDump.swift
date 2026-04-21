extension SwiftPackageManager {
  /// A partial represenation of the output of 'swift package dump-package'. See
  /// ``Self/loadPartialPackageDump(packageDirectory:toolchain:)`` for more.
  struct PartialPackageDump: Sendable, Decodable {
    var dependencies: [Dependency]
    var products: [Product]
    var targets: [Target]

    /// A Partial decoding of package dependencies. We only need this for
    /// associating the `nameForTargetDependencyResolutionOnly` values with
    /// identities, so that's all we parse.
    enum Dependency: Sendable, Decodable {
      case decoded(
        identity: String,
        nameForTargetDependencyResolutionOnly: String?
      )
      case other

      enum CodingKeys: String, CodingKey {
        case fileSystem
        case sourceControl
      }

      struct DTO: Decodable {
        var identity: String
        var nameForTargetDependencyResolutionOnly: String?
      }

      init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Only fileSystem and sourceControl dependencies can have the
        // nameForTargetDependencyResolutionOnly field afaict, so we
        // ignore other dependencies.
        let key: CodingKeys
        if container.contains(.fileSystem) {
          key = .fileSystem
        } else if container.contains(.sourceControl) {
          key = .sourceControl
        } else {
          self = .other
          return
        }

        // Why did SwiftPM have to make this format so strange... I've done my
        // best to describe the error concisely, but I don't think there's really
        // any good description
        let dtos = try container.decode([DTO].self, forKey: key)
        guard let dto = dtos.first else {
          throw DecodingError.dataCorrupted(DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: "Expected at least one entry in dependency encoding, found none"
          ))
        }

        if dtos.count > 1 {
          // It seems extremely unlikely that we'd manage to decode both entries as
          // DTO values if they added an extra entry to the array, but might as well
          // warn about it just in case
          log.warning(
            """
            Expected a single dependency DTO, found multiple. Please report this \
            at \(SwiftBundler.newIssueURL)
            """
          )
        }

        self = .decoded(
          identity: dto.identity,
          nameForTargetDependencyResolutionOnly:
            dto.nameForTargetDependencyResolutionOnly
        )
      }
    }

    /// We only need the product names from the partial package dump (to detect
    /// which products are explicit and which have been synthesized).
    struct Product: Sendable, Decodable {
      var name: String
    }

    struct Target: Sendable, Decodable {
      var name: String
      var dependencies: [TargetDependency]
    }

    enum DependencyCondition: Sendable, Decodable {
      case platform(names: [String])
      case unknown

      enum CodingKeys: String, CodingKey {
        case platformNames
      }

      init(from decoder: any Decoder) throws {
        do {
          let container = try decoder.container(keyedBy: CodingKeys.self)
          let platformNames = try container.decode([String].self, forKey: .platformNames)
          self = .platform(names: platformNames)
        } catch {
          log.warning(
            """
            Failed to parse Swift target dependency condition, skipping. Please \
            open an issue at \(SwiftBundler.newIssueURL). Cause: \
            \(error.localizedDescription)
            """
          )
          self = .unknown
        }
      }
    }

    enum TargetDependency: Sendable, Decodable {
      case byName(String, DependencyCondition?)
      case target(String, DependencyCondition?)
      case product(package: String, product: String, DependencyCondition?)
      case unknown

      enum CodingKeys: String, CodingKey {
        case byName
        case target
        case product
      }

      struct ByName: Sendable, Decodable {
        var name: String
        var condition: DependencyCondition?

        init(from decoder: any Decoder) throws {
          var container = try decoder.unkeyedContainer()
          name = try container.decode(String.self)
          condition = try container.decode(DependencyCondition?.self)
        }
      }

      struct Product: Sendable, Decodable {
        var package: String
        var product: String
        var condition: DependencyCondition?

        init(from decoder: any Decoder) throws {
          var container = try decoder.unkeyedContainer()
          product = try container.decode(String.self)
          package = try container.decode(String.self)
          // Skip module aliases
          _ = try container.decode([String: String]?.self)
          condition = try container.decode(DependencyCondition?.self)
        }
      }

      init(from decoder: any Decoder) throws {
        do {
          let container = try decoder.container(keyedBy: CodingKeys.self)
        
          if container.allKeys.contains(.byName) {
            let dependency = try container.decode(ByName.self, forKey: .byName)
            self = .byName(dependency.name, dependency.condition)
          } else if container.allKeys.contains(.target) {
            let dependency = try container.decode(ByName.self, forKey: .target)
            self = .target(dependency.name, dependency.condition)
          } else {
            let dependency = try container.decode(Product.self, forKey: .product)
            self = .product(
              package: dependency.package,
              product: dependency.product,
              dependency.condition
            )
          }
        } catch {
          log.warning(
            """
            Failed to parse Swift target dependency, skipping. Please open an \
            issue at \(SwiftBundler.newIssueURL). Cause: \
            \(error.localizedDescription)
            """
          )
          self = .unknown
        }
      }
    }
  }
}
