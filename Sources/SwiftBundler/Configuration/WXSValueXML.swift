import XMLCoder

/// A wrapper around ``WXSValue`` to use when encoding to XML.
struct WXSValueXML: Encodable {
  var value: WXSValue

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

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: Key.self)
    try encode(intoContainer: &container)
  }

  func encode<Key: OpenCodingKey>(
    intoContainer container: inout KeyedEncodingContainer<Key>
  ) throws {
    for (key, value) in value.attributes {
      try container.encode(Attribute(value), forKey: Key(key))
    }

    var groupedChildren: [String: [WXSValueXML]] = [:]
    for child in value.children {
      groupedChildren[child.tag, default: []].append(WXSValueXML(value: child))
    }

    for (tag, group) in groupedChildren {
      try container.encode(Element(group), forKey: Key(tag))
    }
  }
}

extension WXSValueXML: Decodable {
  init(from decoder: any Decoder) throws {
    fatalError(
      """
      Decodable not implemented for WXSValueXML; conformance exists to \
      satisfy XMLCoder.Element requirements
      """
    )
  }
}
