import Foundation

extension String {
  /// A quoted version of the string for interpolating into commands.
  /// **This is not secure**, it should only be used in example commands printed to the command-line.
  var quotedIfNecessary: String {
    let specialCharacters: [Character] = [" ", "\\", "\"", "!", "$", "'", "{", "}", ","]
    for character in specialCharacters {
      if self.contains(character) {
        return "'\(self.replacingOccurrences(of: "'", with: "'\\''"))'"
      }
    }
    return self
  }

  /// Writes the string to a file.
  func write(to file: URL) throws {
    try write(to: file, atomically: true, encoding: .utf8)
  }

  /// Gets the string with 'a' or 'an' prepended depending on whether the
  /// word starts with a vowel or not. May not be perfect (English probably
  /// has edge cases).
  var withIndefiniteArticle: String {
    guard let first = first else {
      return self
    }

    if ["a", "e", "i", "o", "u"].contains(first) {
      return "an \(self)"
    } else {
      return "a \(self)"
    }
  }

  /// A stable hash of the string using the djb2 algorithm.
  var stableHash: UInt64 {
    // Ref: http://www.cse.yorku.ca/~oz/hash.html
    // Code adapted from: https://stackoverflow.com/a/39238545
    utf8.reduce(5381) { hash, byte in
      (hash << 5) &+ hash &+ UInt64(byte)
    }
  }
}

extension String.Index {
  func offset(in string: String) -> Int {
    string.distance(from: string.startIndex, to: self)
  }
}
