extension CLIConfiguration {
  /// MSI bundler related configuration properties.
  @Configuration(overlayable: false)
  struct RPM: Codable, Hashable, Sendable {
    /// Only available in overlays with `bundler(linuxRPM)` or stronger. Sets the list of
    /// package dependencies
    @Validate({ (requirements: [String]) throws(ConfigurationFlattener.Error) in
      for requirement in requirements {
        guard RPMBundler.isValidRequirement(requirement) else {
          throw ConfigurationFlattener.Error(
            cause: CLIConfiguration.Error(.invalidRPMRequirement(requirement))
          )
        }
      }
    })
    var requirements: [String] = []
  }
}
