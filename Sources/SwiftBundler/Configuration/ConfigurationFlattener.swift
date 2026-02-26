import Foundation

/// Evaluates a configuration's overlays and performs any other useful
/// transformations or validations at the same time.
enum ConfigurationFlattener {
  struct Context {
    var platform: Platform
    var bundler: BundlerChoice
    var codingPath = CodingPath()

    func appendingCodingKey(_ key: any CodingKey) -> Self {
      var copy = self
      copy.codingPath.keys.append(key)
      return copy
    }

    func appendingCodingKey(_ key: String) -> Self {
      appendingCodingKey(StringCodingKey(key))
    }

    func appendingCodingIndex(_ index: Int) -> Self {
      appendingCodingKey(CodingIndex(index))
    }
  }

  static func flatten(
    _ configuration: PackageConfiguration,
    with context: Context
  ) throws(Error) -> PackageConfiguration.Flat {
    // TODO(stackotter): Switch over to PackageConfiguration.flatten(with:)

    let flattenedApps = try configuration.apps?.mapValues {
        (name, app) throws(Error) -> AppConfiguration.Flat in
      try app.flatten(
        with:
          context
          .appendingCodingKey(PackageConfiguration.CodingKeys.apps)
          .appendingCodingKey(name)
      )
    } ?? [:]

    let flattenedProjects = try configuration.projects?.mapValues {
        (name, project) throws(Error) -> ProjectConfiguration.Flat in
      guard name != ProjectConfiguration.rootProjectName else {
        throw Error(.reservedProjectName(name))
      }
      return try project.flatten(
        with:
          context
          .appendingCodingKey(PackageConfiguration.CodingKeys.projects)
          .appendingCodingKey(name)
      )
    } ?? [:]

    let flattenedBuilders = try configuration.builders?.mapValues {
        (name, builder) throws(Error) -> BuilderConfiguration.Flat in
      guard !name.contains(".") else {
        throw Error(.builderNameContainsPeriod(name))
      }
      return try builder.flatten(
        with: context
          .appendingCodingKey(PackageConfiguration.CodingKeys.builders)
          .appendingCodingKey(name)
      )
    } ?? [:]

    let flattenedTargets = try configuration.targets?.mapValues {
        (name, target) throws(Error) -> TargetConfiguration.Flat in
      try target.flatten(
        with: context
          .appendingCodingKey(PackageConfiguration.CodingKeys.targets)
          .appendingCodingKey(name)
      )
    } ?? [:]

    return PackageConfiguration.Flat(
      formatVersion: configuration.formatVersion,
      apps: flattenedApps,
      projects: flattenedProjects,
      builders: flattenedBuilders,
      targets: flattenedTargets
    )
  }

  static func mergeOverlays<Overlay: ConfigurationOverlay>(
    _ overlays: [Overlay],
    into base: Overlay.Base,
    with context: Context
  ) throws(Error) -> Overlay.Base {
    // Ensure the conditions are met for all present properties
    for overlay in overlays {
      for (exclusiveCondition, properties) in Overlay.exclusiveProperties {
        guard exclusiveCondition != overlay.condition else {
          continue
        }

        let illegalProperties = properties.propertiesPresent(in: overlay)
        guard illegalProperties.isEmpty else {
          let message = ErrorMessage.conditionNotMetForProperties(
            exclusiveCondition,
            properties: illegalProperties
          )
          throw Error(message)
        }
      }
    }

    // Merge overlays into base
    return overlays.filter { (overlay: Overlay) in
      condition(overlay.condition, matches: context)
    }.reduce(into: base) { partialResult, overlay in
      overlay.merge(into: &partialResult)
    }
  }

  static func condition(
    _ condition: OverlayCondition,
    matches context: Context
  ) -> Bool {
    switch condition {
      case .platform(let identifier):
        identifier == context.platform.rawValue
      case .bundler(let identifier):
        identifier == context.bundler.rawValue
    }
  }
}

protocol Flattenable {
  associatedtype Flat

  func flatten(with context: ConfigurationFlattener.Context)
    throws(ConfigurationFlattener.Error) -> Flat
}

protocol TriviallyFlattenable: Flattenable {}

extension TriviallyFlattenable where Flat == Self {
  func flatten(with context: ConfigurationFlattener.Context)
    throws(ConfigurationFlattener.Error) -> Flat
  {
    self
  }
}

extension String: TriviallyFlattenable {}
extension Bool: TriviallyFlattenable {}
extension Int: TriviallyFlattenable {}
extension UInt: TriviallyFlattenable {}
extension Int8: TriviallyFlattenable {}
extension UInt8: TriviallyFlattenable {}
extension Int16: TriviallyFlattenable {}
extension UInt16: TriviallyFlattenable {}
extension Int32: TriviallyFlattenable {}
extension UInt32: TriviallyFlattenable {}
extension Int64: TriviallyFlattenable {}
extension UInt64: TriviallyFlattenable {}
extension Float: TriviallyFlattenable {}
extension Double: TriviallyFlattenable {}
extension MetadataValue: TriviallyFlattenable {}
extension PlistValue: TriviallyFlattenable {}

extension Optional: Flattenable where Wrapped: Flattenable {
  func flatten(with context: ConfigurationFlattener.Context)
    throws(ConfigurationFlattener.Error) -> Wrapped.Flat?
  {
    switch self {
      case .none:
        return nil
      case .some(let value):
        return try value.flatten(with: context)
    }
  }
}

extension Dictionary: Flattenable where Value: Flattenable {
  func flatten(with context: ConfigurationFlattener.Context)
    throws(ConfigurationFlattener.Error) -> [Key: Value.Flat]
  {
    try mapValues { (key, value) throws(ConfigurationFlattener.Error) in
      try value.flatten(with: context)
    }
  }
}

extension Array: Flattenable where Element: Flattenable {
  func flatten(with context: ConfigurationFlattener.Context)
    throws(ConfigurationFlattener.Error) -> [Element.Flat]
  {
    try map { element throws(ConfigurationFlattener.Error) in
      try element.flatten(with: context)
    }
  }
}
