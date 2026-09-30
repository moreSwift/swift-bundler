@attached(member, names: named(Overlay), named(CodingKeys), named(overlays), named(init))
@attached(
  extension,
  conformances: Flattenable, Mergeable,
  names: named(Flat), named(flatten), named(merge)
)
macro Configuration(overlayable: Bool = false) = #externalMacro(
  module: "SwiftBundlerMacrosPlugin",
  type: "ConfigurationMacro"
)

@attached(
  extension,
  conformances: Mergeable,
  names: named(merge)
)
macro Mergeable() = #externalMacro(
  module: "SwiftBundlerMacrosPlugin",
  type: "MergeableMacro"
)

@attached(peer)
macro ConfigurationKey(_ key: String) = #externalMacro(
  module: "SwiftBundlerMacrosPlugin",
  type: "ConfigurationKeyMacro"
)

@attached(peer)
macro Available(_ condition: OverlayCondition) = #externalMacro(
  module: "SwiftBundlerMacrosPlugin",
  type: "AvailableMacro"
)

/// Marks a property as only available from a particular Swift Bundler version onwards.
///
/// - Parameter version: A semantic version that ``Version`` can parse.
@attached(peer)
macro Introduced(in version: String) = #externalMacro(
  module: "SwiftBundlerMacrosPlugin",
  type: "IntroducedMacro"
)

@attached(peer)
macro Aggregate(_ name: String) = #externalMacro(
  module: "SwiftBundlerMacrosPlugin",
  type: "AggregateMacro"
)

@attached(peer)
macro Validate<T>(_ validation: (T) throws(ConfigurationFlattener.Error) -> Void) = #externalMacro(
  module: "SwiftBundlerMacrosPlugin",
  type: "ValidateMacro"
)

@attached(peer)
macro ExcludeFromOverlay() = #externalMacro(
  module: "SwiftBundlerMacrosPlugin",
  type: "ExcludeFromOverlayMacro"
)

@attached(peer)
macro ExcludeFromFlat() = #externalMacro(
  module: "SwiftBundlerMacrosPlugin",
  type: "ExcludeFromFlatMacro"
)
