struct WXSValue: TriviallyFlattenable, Sendable {
  var tag: String
  var attributes: [String: String]
  var children: [WXSValue]
}

extension WXSValue: Codable {
  struct Key: OpenCodingKey, Equatable {
    var stringValue: String

    var intValue: Int? { nil}

    static let tag = Self("tag")
    static let children = Self("children")

    var isSpecial: Bool {
      self == .tag || self == .children
    }

    init?(intValue: Int) {
      return nil
    }

    init(_ stringValue: String) {
      self.stringValue = stringValue
    }
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: Key.self)
    self.tag = try container.decode(String.self, forKey: .tag)

    if container.contains(.children) {
      let children = try container.decode([WXSValue].self, forKey: .children)
      self.children = children
    } else {
      self.children = []
    }

    var keys = container.allKeys
    keys = keys.filter { !$0.isSpecial }
    attributes = [:]
    for key in keys {
      let value = try container.decode(String.self, forKey: key)
      attributes[key.stringValue] = value
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Key.self)
    try container.encode(tag, forKey: .tag)
    try container.encode(children, forKey: .children)
    for (key, value) in attributes {
      try container.encode(value, forKey: Key(key))
    }
  }
}
