/// The arguments to a template. These values are used to create projects from templates.
struct TemplateArguments {
  /// The name of the package.
  var packageName: String
  /// The package's configuration.
  var configuration: AppConfiguration
  /// The indentation style to use.
  var indentationStyle: IndentationStyle
  /// If `true`, the VSCode overlay (containing `launch.json` and `.vscode/tasks.json`),
  var addVSCodeOverlay: Bool
}
