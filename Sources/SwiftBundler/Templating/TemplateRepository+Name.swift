import ArgumentParser
import Foundation

extension TemplateRepository {
  /// A template repository name.
  struct Name: Codable, Hashable, Sendable, CustomStringConvertible, ExpressibleByArgument {
    /// The name of the default template repository.
    static let `default` = Self(assumingValid: "default")

    /// The set of characters allowed in template repository names.
    static let validNameCharacters = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
    )

    /// Validates a candidate template repository name.
    static func validateName(_ name: String) -> Bool {
      name.unicodeScalars.allSatisfy { character in
        validNameCharacters.contains(character)
      }
    }

    /// The underlying validated name.
    let name: String

    /// Creates a validated template repository name.
    /// - Returns: `nil` if the name is invalid.
    init?(_ name: String) {
      guard Self.validateName(name) else {
        return nil
      }
      self.name = name
    }

    init?(argument: String) {
      self.init(argument)
    }

    var description: String {
      name
    }

    /// An escape hatch for creating known-good names at compile time.
    private init(assumingValid name: String) {
      self.name = name
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      let name = try container.decode(String.self)
      guard Self.validateName(name) else {
        throw TemplateRepositoryManager.Error(
          .invalidTemplateRepositoryName(name)
        )
      }
      self.name = name
    }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(name)
    }
  }
}
