import ErrorKit
import Foundation
import TOMLKit

/// An error mapper used by Swift Bundler to provide nicer variants of certain
/// third-party errors.
public enum SwiftBundlerErrorMapper: ErrorMapper {
  public static func userFriendlyMessage(for error: Error) -> String? {
    switch error {
      case DecodingError.keyNotFound(let codingKey, let context):
        if codingKey.stringValue == "bundle_identifier" {
          return "'bundle_identifier' is required for app configuration to be migrated"
        } else {
          let path = CodingPath(context.codingPath)
          return "Expected a value at '\(path)'"
        }
      case let error as UnexpectedKeysError:
        if error.keys.count == 1, let path = error.keys.values.first {
          return "Encountered unexpected key '\(CodingPath(path))'"
        } else {
          let paths = error.keys.values.map(CodingPath.init)
          let pathsString = paths.map { "'\($0.description)'" }.joinedGrammatically()
          return """
            Encountered unexpected \(paths.count == 1 ? "key" : "keys") \
            \(pathsString)
            """
        }
      case DecodingError.typeMismatch(_, let context):
        return """
          Decoding error at '\(CodingPath(context.codingPath))'; \
          \(context.debugDescription)
          """
      default:
        return nil
    }
  }
}
