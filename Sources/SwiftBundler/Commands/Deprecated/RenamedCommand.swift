import ArgumentParser

/// A protocol to simplify creation of hidden deprecated copies of commands.
protocol RenamedCommand: AsyncParsableCommand {
  associatedtype Wrapped: AsyncParsableCommand

  static var original: String { get }
  static var new: String { get }
  /// A subcommand to use as the default subcommand. By default the command will
  /// have no default subcommand.
  ///
  /// Swift Bundler no longer uses default subcommands, but some deprecated
  /// spellings of commands had default subcommands. By providing the old
  /// default subcommand here, we avoid breaking existing scripts.
  static var defaultSubcommand: (any ParsableCommand.Type)? { get }

  var wrappedCommand: Wrapped { get set }
}

extension RenamedCommand {
  static var name: String {
    original.split(separator: " ").last.map(String.init(_:)) ?? new
  }

  static var defaultSubcommand: (any ParsableCommand.Type)? {
    nil
  }

  static var configuration: CommandConfiguration {
    CommandConfiguration(
      commandName: name,
      abstract: """
        Deprecated version of 'swift-bundler \(new)' provided for backwards \
        compatibility.
        """,
      shouldDisplay: false,
      subcommands: Wrapped.configuration.subcommands,
      defaultSubcommand: defaultSubcommand
    )
  }

  mutating func validate() throws {
    log.warning(
      """
      'swift-bundler \(Self.original)' has been deprecated; use \
      'swift-bundler \(Self.new)' instead
      """
    )
    try wrappedCommand.validate()
  }

  mutating func run() async throws {
    try await wrappedCommand.run()
  }
}
