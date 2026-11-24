import ArgumentParser
import Foundation

struct DeprecatedListIdentitiesCommand: RenamedCommand {
  typealias Wrapped = IdentityListCommand

  static let original = "list-identities"
  static let new = "identity ls"

  @OptionGroup
  var wrappedCommand: Wrapped
}

struct DeprecatedMigrateCommand: RenamedCommand {
  typealias Wrapped = ConfigMigrateCommand

  static let original = "migrate"
  static let new = "config migrate"

  @OptionGroup
  var wrappedCommand: Wrapped
}

struct DeprecatedDevicesCommand: RenamedCommand {
  typealias Wrapped = DeviceCommand

  static let original = "devices"
  static let new = "device"
  static let defaultSubcommand: (any ParsableCommand.Type)? = DeprecatedDeviceListCommand.self

  @OptionGroup
  var wrappedCommand: Wrapped
}

struct DeprecatedSimulatorsCommand: RenamedCommand {
  typealias Wrapped = SimulatorCommand

  static let original = "simulators"
  static let new = "simulator"
  static let defaultSubcommand: (any ParsableCommand.Type)? = DeprecatedSimulatorListCommand.self

  @OptionGroup
  var wrappedCommand: Wrapped
}

struct DeprecatedTemplatesCommand: RenamedCommand {
  typealias Wrapped = TemplateCommand

  static let original = "templates"
  static let new = "template"
  static let defaultSubcommand: (any ParsableCommand.Type)? = DeprecatedTemplateListCommand.self

  @OptionGroup
  var wrappedCommand: Wrapped
}

struct DeprecatedDeviceListCommand: RenamedCommand {
  typealias Wrapped = DeviceListCommand

  static let original = "device list"
  static let new = "device ls"

  @OptionGroup
  var wrappedCommand: Wrapped
}

struct DeprecatedSimulatorListCommand: RenamedCommand {
  typealias Wrapped = SimulatorListCommand

  static let original = "simulator list"
  static let new = "simulator ls"

  @OptionGroup
  var wrappedCommand: Wrapped
}

struct DeprecatedTemplateListCommand: RenamedCommand {
  typealias Wrapped = TemplateListCommand

  static let original = "template list"
  static let new = "template ls"

  @OptionGroup
  var wrappedCommand: Wrapped
}

struct DeprecatedConfigAppsCommand: RenamedCommand {
  typealias Wrapped = ConfigAppCommand

  static let original = "config apps"
  static let new = "config app"
  static let defaultSubcommand: (any ParsableCommand.Type)? = DeprecatedConfigAppListCommand.self

  @OptionGroup
  var wrappedCommand: Wrapped
}

struct DeprecatedConfigAppListCommand: RenamedCommand {
  typealias Wrapped = ConfigAppListCommand

  static let original = "config app list"
  static let new = "config app ls"

  @OptionGroup
  var wrappedCommand: Wrapped
}
