import ArgumentParser
import Foundation

// Fully qualified protocol names used to silence retroactive conformance warning
// while still supporting older Swift versions (from before the @retroactive
// marker).
extension Array: ArgumentParser.ExpressibleByArgument
where Element: ArgumentParser.ExpressibleByArgument {
  public var defaultValueDescription: String {
    "[" + self.map(\.defaultValueDescription).joined(separator: ", ") + "]"
  }

  public init?(argument: String) {
    return nil
  }
}

extension Array {
  /// A typed-throws version of `compactMap`.
  func compactMap<NewElement, E: Error>(
    _ transform: (Element) throws(E) -> NewElement?
  ) throws(E) -> [NewElement] {
    var result: [NewElement] = []
    for element in self {
      if let newElement = try transform(element) {
        result.append(newElement)
      }
    }
    return result
  }

  /// A typed-throws version of `map`.
  func map<NewElement, E: Error>(
    _ transform: (Element) throws(E) -> NewElement
  ) throws(E) -> [NewElement] {
    var result: [NewElement] = []
    for element in self {
      result.append(try transform(element))
    }
    return result
  }

  /// A typed-throws version of `flatMap`.
  func flatMap<NewElement, E: Error>(
    _ transform: (Element) throws(E) -> [NewElement]
  ) throws(E) -> [NewElement] {
    var result: [NewElement] = []
    for element in self {
      result.append(contentsOf: try transform(element))
    }
    return result
  }
}

struct Verb {
  var singular: String
  var plural: String

  static let be = Verb(singular: "is", plural: "are")
}

extension Array<String> {
  func joinedGrammatically(
    singular: String,
    plural: String,
    withTrailingVerb trailingVerb: Verb?
  ) -> String {
    let base: String
    if count == 0 {
      base = "No \(plural)"
    } else if count == 1 {
      base = "The \(singular)"
    } else {
      base = "The \(plural)"
    }

    return "\(base) \(joinedGrammatically(withTrailingVerb: trailingVerb))"
  }

  func joinedGrammatically(
    withTrailingVerb trailingVerb: Verb? = nil
  ) -> String {
    let base: String
    let requiresPluralVerb: Bool
    if count == 0 {
      return trailingVerb?.plural ?? ""
    } else if count == 1 {
      base = "\(self[0])"
      requiresPluralVerb = false
    } else {
      base = """
        \(self[0..<(count - 1)].joined(separator: ", ")) and \(self[count - 1])
        """
      requiresPluralVerb = true
    }

    if let trailingVerb {
      if requiresPluralVerb {
        return "\(base) \(trailingVerb.plural)"
      } else {
        return "\(base) \(trailingVerb.singular)"
      }
    } else {
      return base
    }
  }
}
