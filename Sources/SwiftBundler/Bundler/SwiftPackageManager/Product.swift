extension SwiftPackageManager {
  /// A package product.
  struct Product: Codable, Sendable {
    /// The product's name.
    var name: String
    /// The product's type.
    var productType: ProductType
    /// The product's targets.
    var targets: [String]
  }
}
