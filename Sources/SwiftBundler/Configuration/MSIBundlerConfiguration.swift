import Foundation
import XMLCoder

@Configuration(overlayable: false)
struct MSIBundlerConfiguration: Codable, Sendable {
  /// Additional entries to add to the app's WXS configuration file before
  /// invoking the WiX CLI to produce the final MSI.
  ///
  /// For example, here's how you could set your app to auto-launch using
  /// custom WiX actions.
  ///
  /// ```toml
  /// msi.wxs_extras = [
  ///   {
  ///     tag = "CustomAction",
  ///     Id = "LaunchApplication",
  ///     Execute = "immediate",
  ///     Impersonate = "no",
  ///     Return = "asyncNoWait",
  ///     Directory = "InstallFolder",
  ///     ExeCommand = "[#MainExecutable]",
  ///   },
  ///   {
  ///     tag = "InstallExecuteSequence",
  ///     children = [
  ///       {
  ///         tag = "Custom",
  ///         Action = "LaunchApplication",
  ///         After = "InstallFinalize",
  ///       }
  ///     ]
  ///   },
  /// ]
  /// ```
  var wxsExtras: [WXSValue]?
}
