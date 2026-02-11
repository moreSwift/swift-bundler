/// A component that displays a list of entries, each on a new line.
struct List: OutputComponent {
  /// The list's entries.
  var entries: [Entry]

  var body: String {
    for entry in entries {
      entry.body
    }
  }

  /// An entry in a list.
  struct Entry: OutputComponent {
    var content: String

    var body: String {
      "* " + content
    }

    /// Creates a list entry.
    init(_ content: String) {
      self.content = content
    }

    /// Creates a list entry.
    init(@OutputBuilder _ content: () -> String) {
      self.content = content()
    }
  }

  /// Creates a component to display a list of entries.
  /// - Parameter content: The entries to display.
  init(@ListBuilder _ content: () -> [Entry]) {
    self.entries = content()
  }

  /// Creates a component to display a list of entries.
  /// - Parameter entries: The entries to display.
  init(_ entries: [Entry]) {
    self.entries = entries
  }
}
