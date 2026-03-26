import Foundation
import TOMLKit

/// A representation of a property list value suitable for losslessly encoding and decoding
/// to and from formats such as JSON and TOML.
///
/// When a value can not be losslessly encoded as a regular single value, it is encoded as
/// a dictionary containing a `type` field and a `value` field. This ensures that the original
/// type is not lost and allows every single possible plist value to be losslessly stored in
/// formats such as JSON or TOML. Below is an example of an explicitly typed date value:
///
/// ```json
/// {
///   "type": "date",
///   "value": "2022-05-18T00:54:55Z"
/// }
/// ```
enum PlistValue: Codable, Equatable, VariableEvaluatable, Sendable {
  /// The JSON schema for a plist value.
  private static var schema = """
    {
      "type": ["number", "string", "object", "array", "boolean"]
    }
    """

  case dictionary([String: PlistValue])
  case array([PlistValue])
  case real(Double)
  case integer(Int)
  case boolean(Bool)
  case date(Date)
  case data(Data)
  case string(String)

  var stringValue: String? {
    switch self {
      case .string(let value):
        return value
      default:
        return nil
    }
  }

  var dictionaryValue: [String: PlistValue]? {
    switch self {
      case .dictionary(let value):
        return value
      default:
        return nil
    }
  }

  var arrayValue: [PlistValue]? {
    switch self {
      case .array(let value):
        return value
      default:
        return nil
    }
  }

  /// A string representation of the value's explicit type.
  var type: String {
    switch self {
      case .dictionary:
        return "dict"
      case .array:
        return "array"
      case .real:
        return "real"
      case .integer:
        return "integer"
      case .boolean:
        return "boolean"
      case .date:
        return "date"
      case .data:
        return "data"
      case .string:
        return "string"
    }
  }

  /// `true` if an explicit type is required to unambiguously decode the value.
  var requiresExplicitType: Bool {
    switch self {
      case .data:
        return true
      case .dictionary(let dictionary):
        // Avoid confusing the dictionary for an explicitly typed value.
        return dictionary[CodingKeys.type.rawValue] != nil
      case .real(let number):
        // Avoid interpreting the real number as an integer
        return Double(Int(number)) == number
      case .array, .integer, .boolean, .date, .string:
        return false
    }
  }

  /// This value's value represented using regular Swift types. Used when serializing to plist.
  var value: Any {
    switch self {
      case .dictionary(let dictionary):
        return dictionary.mapValues(\.value)
      case .array(let array):
        return array.map(\.value)
      case .real(let double):
        return double
      case .integer(let integer):
        return integer
      case .boolean(let boolean):
        return boolean
      case .date(let date):
        return date
      case .data(let data):
        return data
      case .string(let string):
        return string
    }
  }

  /// Coding keys used by explicitly typed value containers.
  enum CodingKeys: String, CodingKey {
    case type
    case value
  }

  // swiftlint:disable:next cyclomatic_complexity
  init(from decoder: Decoder) throws {
    // Attempt to decode the value as an explicitly typed value.
    if let container = try? decoder.container(keyedBy: CodingKeys.self) {
      if let value = try Self.decodeExplicitlyTypedValue(from: container) {
        self = value
        return
      }
    }

    // Attempt to infer the type of the implicitly typed value.
    if let container = try? decoder.singleValueContainer() {
      if let string = try? container.decode(String.self) {
        if let date = ISO8601DateFormatter().date(from: string) {
          self = .date(date)
        } else {
          self = .string(string)
        }
      } else if let integer = try? container.decode(Int.self) {
        self = .integer(integer)
      } else if let number = try? container.decode(Double.self) {
        if Double(Int(number)) == number {
          self = .integer(Int(number))
        } else {
          self = .real(number)
        }
      } else if let boolean = try? container.decode(Bool.self) {
        self = .boolean(boolean)
      } else if let array = try? container.decode([PlistValue].self) {
        self = .array(array)
      } else if let dictionary = try? container.decode([String: PlistValue].self) {
        self = .dictionary(dictionary)
      } else {
        throw Error(.failedToInferType(codingPath: decoder.codingPath))
      }
    } else {
      throw Error(.failedToInferType(codingPath: decoder.codingPath))
    }
  }

  /// Decodes a value with an explicit type.
  ///
  /// Below is an example of an explicitly typed value (in JSON form):
  ///
  /// ```json
  /// {
  ///   "type": "date",
  ///   "value": "2022-05-18T00:54:55Z"
  /// }
  /// ```
  static func decodeExplicitlyTypedValue(  // swiftlint:disable:this cyclomatic_complexity
    from container: KeyedDecodingContainer<CodingKeys>
  ) throws -> PlistValue? {
    let type: String
    do {
      type = try container.decode(String.self, forKey: .type)
    } catch {
      return nil
    }

    do {
      switch type {
        case "dict":
          return .dictionary(try container.decode([String: PlistValue].self, forKey: .value))
        case "array":
          return .array(try container.decode([PlistValue].self, forKey: .value))
        case "real":
          return .real(try container.decode(Double.self, forKey: .value))
        case "integer":
          return .integer(try container.decode(Int.self, forKey: .value))
        case "boolean":
          return .boolean(try container.decode(Bool.self, forKey: .value))
        case "date":
          let string = try container.decode(String.self, forKey: .value)
          guard let date = ISO8601DateFormatter().date(from: string) else {
            let message = ErrorMessage.invalidValue(
              string, type: "ISO8601 date", codingPath: container.codingPath
            )
            throw Error(message)
          }
          return .date(date)
        case "data":
          let base64 = try container.decode(String.self, forKey: .value)
          guard let data = Data(base64Encoded: base64) else {
            let message = ErrorMessage.invalidValue(
              base64, type: "base64 data", codingPath: container.codingPath
            )
            throw Error(message)
          }
          return .data(data)
        case "string":
          return .string(try container.decode(String.self, forKey: .value))
        default:
          let message = ErrorMessage.invalidValue(
            type, type: "plist data type", codingPath: container.codingPath
          )
          throw Error(message)
      }
    } catch let error as Error {
      throw error
    } catch {
      throw Error(.invalidExplicitlyTypedValue(type: type, codingPath: container.codingPath))
    }
  }

  func encode(to encoder: Encoder) throws {
    let valueEncoder: Encoder
    if requiresExplicitType {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(type, forKey: .type)
      valueEncoder = container.superEncoder(forKey: .value)
    } else {
      valueEncoder = encoder
    }

    switch self {
      case .dictionary(let dictionary):
        try dictionary.encode(to: valueEncoder)
      case .array(let array):
        try array.encode(to: valueEncoder)
      case .real(let real):
        try real.encode(to: valueEncoder)
      case .integer(let integer):
        try integer.encode(to: valueEncoder)
      case .boolean(let boolean):
        try boolean.encode(to: valueEncoder)
      case .date(let date):
        let string = ISO8601DateFormatter().string(from: date)
        try string.encode(to: valueEncoder)
      case .data(let data):
        let string = data.base64EncodedString()
        try string.encode(to: valueEncoder)
      case .string(let string):
        try string.encode(to: valueEncoder)
    }
  }

  /// Loads a dictionary of ``PlistValue``s from a plist file.
  /// - Parameter plistFile: The plist file to load the dictionary from.
  /// - Returns: The loaded plist dictionary.
  static func loadDictionary(
    fromPlistFile plistFile: URL
  ) throws(Error) -> [String: PlistValue] {
    let contents: Data
    do {
      contents = try Data(contentsOf: plistFile)
    } catch {
      throw Error(.failedToReadInfoPlistFile, cause: error)
    }

    let dictionary: [String: Any]
    do {
      var propertyListFormat = PropertyListSerialization.PropertyListFormat.xml
      guard
        let plist = try PropertyListSerialization.propertyList(
          from: contents,
          options: .mutableContainersAndLeaves,
          format: &propertyListFormat
        ) as? [String: Any]
      else {
        throw Error(.failedToDeserializePlistFileContents(contents))
      }

      dictionary = plist
    } catch let error as Error {
      throw error
    } catch {
      throw Error(.failedToDeserializePlistFileContents(contents), cause: error)
    }

    return try convert(dictionary)
  }

  /// Converts a Swift dictionary to a dictionary of ``PlistValue``s.
  /// - Parameter value: The value to convert.
  /// - Returns: The converted value.
  static func convert(_ dictionary: [String: Any]) throws(Error) -> [String: PlistValue] {
    try dictionary.mapValues { (key, value) throws(Error) in
      try convert(value)
    }
  }

  /// Converts a Swift value to a ``PlistValue``.
  /// - Parameter value: The value to convert.
  /// - Returns: The converted value.
  static func convert(_ value: Any) throws(Error) -> PlistValue {
    if let string = value as? String {
      return .string(string)
    } else if let date = value as? Date {
      return .date(date)
    } else if let integer = value as? Int {
      return .integer(integer)
    } else if let double = value as? Double {
      return .real(double)
    } else if let boolean = value as? Bool {
      return .boolean(boolean)
    } else if let array = value as? [Any] {
      return .array(try array.map(convert))
    } else if let dictionary = value as? [String: Any] {
      return .dictionary(try convert(dictionary))
    } else {
      throw Error(.invalidPlistValue(description: "\(value)"))
    }
  }
}
