import MacroToolkit
import SwiftSyntax
import SwiftSyntaxMacros

public struct MergeableMacro {}

extension MergeableMacro: ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    let attribute = MacroAttribute(node)
    guard attribute.arguments.isEmpty else {
      throw MacroError("usage: @Mergeable()")
    }

    guard let structDecl = Decl(declaration).asStruct else {
      throw MacroError("@Mergeable must be attached to a struct")
    }

    // TODO(stackotter): We should probably use different property parsing logic
    //   when used without the Configuration macro? i.e. we should probably ignore
    //   Configuration-specific attached property macros?
    let properties = try ConfigurationMacro.extractConfigurationProperties(structDecl)

    return [
      try generateMergeableExtension(type: type, structDecl: structDecl, properties: properties)
    ]
  }

  static func generateMergeableExtension(
    type: some TypeSyntaxProtocol,
    structDecl: Struct,
    properties: [ConfigurationProperty]
  ) throws -> ExtensionDeclSyntax {
    try ExtensionDeclSyntax("extension \(type): Mergeable") {
      DeclSyntax(try generateMergeMethod(
        structDecl,
        properties
      ))
    }
  }

  static func generateMergeMethod(
    _ type: Struct,
    _ properties: [ConfigurationProperty]
  ) throws -> FunctionDeclSyntax {
    return try FunctionDeclSyntax(
      "static func merge(_ base: Self, _ overlay: Self) -> Self"
    ) {
      StmtSyntax("\nvar base = base")
      for property in properties {
        let name = property.identifier
        StmtSyntax("\nConfigurationHelpers.merge(&base.\(raw: name), overlay.\(raw: name))")
      }

      ReturnStmtSyntax(
        returnKeyword: .keyword(.return),
        expression: ExprSyntax("base")
      )
    }
  }
}
