import Foundation
import ErrorKit

extension ConfigurationFlattener {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``ConfigurationFlattener``.
  enum ErrorMessage: Throwable {
    case conditionNotMetForProperties(
      OverlayCondition,
      properties: [String]
    )
    case reservedProjectName(String)
    case localSourceMustNotSpecifyRevision(_ path: String)
    case defaultSourceMissingAPIRequirement
    case gitSourceMissingAPIRequirement(_ url: URL, field: CodingPath)
    case builderNameContainsPeriod(_ name: String)
    case filenameContainsPathSeparator(String)
    case sourceAndBuilderMustHaveSameNilness

    var userFriendlyMessage: String {
      switch self {
        case .conditionNotMetForProperties(let condition, let properties):
          let propertyList = properties.map { "'\($0)'" }.joinedGrammatically(
            singular: "property",
            plural: "properties",
            withTrailingVerb: Verb.be
          )
          return """
            \(propertyList) only available in overlays meeting the condition \
            '\(condition)'
            """
        case .reservedProjectName(let name):
          return "The project name '\(name)' is reserved"
        case .localSourceMustNotSpecifyRevision(let path):
          return "'api' field is redundant when local builder API is used ('local(\(path))')"
        case .defaultSourceMissingAPIRequirement:
          return "Default Builder API missing API requirement (provide the 'api' field)"
        case .gitSourceMissingAPIRequirement(_, let field):
          return """
            Builder API sourced from git missing API requirement (provide the \
            '\(field)' field)
            """
        case .builderNameContainsPeriod(let name):
          return "Builder names must not contain periods, got '\(name)'"
        case .filenameContainsPathSeparator(let filename):
          return """
            Filename '\(filename)' contains a path separator. Use \
            outputDirectory to specify alternative search location within \
            project build directory
            """
        case .sourceAndBuilderMustHaveSameNilness:
          return """
            The 'source' and 'builder' fields of a project must either be both \
            present, or both not present
            """
      }
    }
  }
}
