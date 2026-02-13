/// A convenient way to create the entries for an ``KeyedList``.
@resultBuilder struct KeyedListBuilder {
  static func buildBlock(_ components: KeyedList.Entry...) -> [KeyedList.Entry] {
    components
  }

  static func buildBlock(_ component: Void) -> [KeyedList.Entry] {
    []
  }

  static func buildBlock(_ components: [KeyedList.Entry]...) -> [KeyedList.Entry] {
    components.flatMap { $0 }
  }

  static func buildArray(_ components: [[KeyedList.Entry]]) -> [KeyedList.Entry] {
    components.flatMap { $0 }
  }

  static func buildOptional(_ component: [KeyedList.Entry]?) -> [KeyedList.Entry] {
    component ?? []
  }

  static func buildEither(first component: [KeyedList.Entry]) -> [KeyedList.Entry] {
    component
  }

  static func buildEither(second component: [KeyedList.Entry]) -> [KeyedList.Entry] {
    component
  }
}
