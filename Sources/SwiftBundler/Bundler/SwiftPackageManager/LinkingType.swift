extension SwiftPackageManager {
  /// The linking type of a library product.
  enum LinkingType: String, Codable, Sendable, Hashable {
    /// The default linking type. SwiftPM adapts the linking of the product to
    /// the context of the build.
    case automatic
    /// The library gets built as a static library.
    case `static`
    /// The library gets built as a dynamic library.
    case dynamic
  }
}
