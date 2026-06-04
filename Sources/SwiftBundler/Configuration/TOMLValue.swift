import TOMLKit

/// A decoded TOML value. Used to consume keys that Swift Bundler is
/// intentionally skipping, or to store unhandled configuration that must
/// be parsed or re-encoded at a later point in time.
indirect enum TOMLValue: Codable, Hashable, Sendable {
  case dateTime(TOMLDateTime)
  case date(TOMLDate)
  case time(TOMLTime)
  case array([TOMLValue])
  case table([String: TOMLValue])
  case string(String)
  case integer(Int)
  case double(Double)
  case boolean(Bool)

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let dateTime = try? container.decode(TOMLDateTime.self) {
      self = .dateTime(dateTime)
    } else if let date = try? container.decode(TOMLDate.self) {
      self = .date(date)
    } else if let time = try? container.decode(TOMLTime.self) {
      self = .time(time)
    } else if let array = try? container.decode([TOMLValue].self) {
      self = .array(array)
    } else if let table = try? container.decode([String: TOMLValue].self) {
      self = .table(table)
    } else if let string = try? container.decode(String.self) {
      self = .string(string)
    } else if let integer = try? container.decode(Int.self) {
      self = .integer(integer)
    } else if let double = try? container.decode(Double.self) {
      self = .double(double)
    } else if let boolean = try? container.decode(Bool.self) {
      self = .boolean(boolean)
    } else {
      throw Error(.failedToDecodeTOMLValue(CodingPath(container.codingPath)))
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
      case let .dateTime(value):
        try container.encode(value)
      case let .date(value):
        try container.encode(value)
      case let .time(value):
        try container.encode(value)
      case let .array(value):
        try container.encode(value)
      case let .table(value):
        try container.encode(value)
      case let .string(value):
        try container.encode(value)
      case let .integer(value):
        try container.encode(value)
      case let .double(value):
        try container.encode(value)
      case let .boolean(value):
        try container.encode(value)
    }
  }
}
