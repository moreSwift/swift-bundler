// Taken from https://github.com/swiftlang/swift-syntax/blob/99c35a75ee92b652a86338c0a23f6ecd906fd722/Sources/SwiftSyntaxBuilder/ConvenienceInitializers.swift#L251-L300
// We would just depend on SwiftSyntax directly, but that slows down our release
// builds by an unacceptable amount.

extension String {
  /// Replace literal newlines with "\r", "\n", "\u{2028}", and ASCII control characters with "\0", "\u{7}"
  public func escapingForStringLiteral(usingDelimiter delimiter: String, isMultiline: Bool) -> String {
    // String literals cannot contain "unprintable" ASCII characters (control
    // characters, etc.) besides tab. As a matter of style, we also choose to
    // escape Unicode newlines like "\u{2028}" even though swiftc will allow
    // them in string literals.
    func needsEscaping(_ scalar: UnicodeScalar) -> Bool {
      if Character(scalar).isNewline {
        return true
      }

      if !scalar.isASCII || scalar.isPrintableASCII {
        return false
      }

      if scalar == "\t" {
        // Tabs need to be escaped in single-line string literals but not
        // multi-line string literals.
        return !isMultiline
      }
      return true
    }

    // Work at the Unicode scalar level so that "\r\n" isn't combined.
    var result = String.UnicodeScalarView()
    var input = self.unicodeScalars[...]
    while let firstNewline = input.firstIndex(where: needsEscaping(_:)) {
      result += input[..<firstNewline]

      result += "\\\(delimiter)".unicodeScalars
      switch input[firstNewline] {
      case "\r":
        result += "r".unicodeScalars
      case "\n":
        result += "n".unicodeScalars
      case "\t":
        result += "t".unicodeScalars
      case "\0":
        result += "0".unicodeScalars
      case let other:
        result += "u{\(String(other.value, radix: 16))}".unicodeScalars
      }
      input = input[input.index(after: firstNewline)...]
    }
    result += input

    return String(result)
  }
}

fileprivate extension Unicode.Scalar {
  /// Whether this character represents a printable ASCII character,
  /// for the purposes of pattern parsing.
  var isPrintableASCII: Bool {
    // Exclude non-printables before the space character U+20, and anything
    // including and above the DEL character U+7F.
    return self.value >= 0x20 && self.value < 0x7F
  }
}
