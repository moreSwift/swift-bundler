extension SwiftPackageManager {
  /// The type of a product.
  enum ProductType: Codable, Sendable, Hashable {
    /// An executable product.
    case executable
    /// A library product.
    case library(linkingType: LinkingType)
    /// A plugin product.
    case plugin
    /// A macro product.
    case macro
  }
}
