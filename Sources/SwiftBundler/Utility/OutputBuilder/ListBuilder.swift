/// A convenient way to create the entries for a ``List``.
@resultBuilder struct ListBuilder {
  static func buildBlock(_ components: List.Entry...) -> [List.Entry] {
    components
  }

  static func buildBlock(_ components: [List.Entry]...) -> [List.Entry] {
    components.flatMap { $0 }
  }

  static func buildArray(_ components: [[List.Entry]]) -> [List.Entry] {
    components.flatMap { $0 }
  }

  static func buildOptional(_ component: [List.Entry]?) -> [List.Entry] {
    component ?? []
  }

  static func buildEither(first component: [List.Entry]) -> [List.Entry] {
    component
  }

  static func buildEither(second component: [List.Entry]) -> [List.Entry] {
    component
  }
}
