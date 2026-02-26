import Foundation
import ErrorKit

/// Essentially just a ``Codable`` TOML value used for arbitrary TOMl values
/// in the Swift Bundler configuration format.
enum MetadataValue: Codable, VariableEvaluatable, Sendable {
  case string(String)
  case integer(Int)
  case double(Double)
  case boolean(Bool)
  case date(Date)
  case array([MetadataValue])
  case dictionary([String: MetadataValue])

  var stringValue: String? {
    switch self {
      case .string(let value):
        return value
      default:
        return nil
    }
  }

  var dictionaryValue: [String: MetadataValue]? {
    switch self {
      case .dictionary(let value):
        return value
      default:
        return nil
    }
  }

  var arrayValue: [MetadataValue]? {
    switch self {
      case .array(let value):
        return value
      default:
        return nil
    }
  }

  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``MetadataValue``.
  enum ErrorMessage: Throwable {
    case unhandledType

    var userFriendlyMessage: String {
      switch self {
        case .unhandledType:
          return "Expected string, number, boolean, date, array, or dictionary"
      }
    }
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode(Int.self) {
      self = .integer(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(Bool.self) {
      self = .boolean(value)
    } else if let value = try? container.decode(Date.self) {
      self = .date(value)
    } else if let value = try? container.decode([MetadataValue].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: MetadataValue].self) {
      self = .dictionary(value)
    } else {
      throw Error(.unhandledType)
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
      case .string(let value):
        try container.encode(value)
      case .integer(let value):
        try container.encode(value)
      case .double(let value):
        try container.encode(value)
      case .boolean(let value):
        try container.encode(value)
      case .date(let value):
        try container.encode(value)
      case .array(let value):
        try container.encode(value)
      case .dictionary(let value):
        try container.encode(value)
    }
  }
}
