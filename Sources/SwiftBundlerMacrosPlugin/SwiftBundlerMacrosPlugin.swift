import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SwiftBundlerMacrosPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    ConfigurationMacro.self,
    MergeableMacro.self,
    ConfigurationKeyMacro.self,
    AvailableMacro.self,
    AggregateMacro.self,
    ValidateMacro.self,
    ExcludeFromOverlayMacro.self,
    ExcludeFromFlatMacro.self
  ]
}
