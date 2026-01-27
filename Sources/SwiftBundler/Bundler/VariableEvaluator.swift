import Foundation
import Version
import Parsing

// Due to https://github.com/swiftlang/swift/issues/83510, we need to 'decouple'
// the typed throws of some called methods from their enclosing methods. These
// are what the methods ending with `Workaround` are for.

/// A utility for evaluating strings containing variables of the form `...$(VARIABLE)...`.
enum VariableEvaluator {
  /// The contextual information required to evaluate variables.
  struct Context {
    /// The app's name.
    var appName: String
    /// The app's product name.
    var productName: String
    /// The current date as of the beginning of variable evaluation.
    var date: Date
    /// The root directory of the package.
    var packageDirectory: URL?
    /// The app's version.
    var version: Version?
    /// The app's identifier.
    var identifier: String?
  }

  /// An evaluator for evaluating the values of variables.
  enum Evaluator {
    case `default`(Context)
    case custom((String) throws(Error) -> String)
  }

  /// Evaluates the variables present in a string with the default evaluator.
  /// - Parameters:
  ///   - string: The string to evaluate variables in.
  ///   - context: The context required to evaluate variables.
  /// - Returns: The evaluated string.
  static func evaluateVariables(
    in string: String,
    with context: Context
  ) async throws(Error) -> String {
    try await evaluateVariables(in: string, with: .`default`(context))
  }

  /// See top of file for explanation.
  private static func evaluateVariablesWorkaround(
    in string: String,
    with context: Context
  ) async throws -> String {
    try await evaluateVariables(in: string, with: .`default`(context))
  }

  /// Evaluates the variables present in a string.
  /// - Parameters:
  ///   - string: The string to evaluate variables in.
  ///   - evaluator: The evaluator to use when evaluating each variable.
  ///   - openingDelimiter: The opening delimiter for a variable. Defaults to `$(`.
  ///   - closingDelimiter: The closing delimiter for a variable. Defaults to `)`.
  /// - Returns: The evaluated string.
  static func evaluateVariables(
    in string: String,
    with evaluator: Evaluator,
    openingDelimiter: String = "$(",
    closingDelimiter: String = ")"
  ) async throws(Error) -> String {
    var input = string[...]
    var output = ""

    // Create parser from delimiters
    let parser = Parse {
      OneOf {
        PrefixUpTo(openingDelimiter).map(String.init)
        Rest<Substring>().map(String.init)
        End<Substring>().map { _ in
          ""
        }
      }
      OneOf {
        Parse(Optional.some(_:)) {
          openingDelimiter
          PrefixUpTo(closingDelimiter).map(String.init)
          closingDelimiter
        }

        Parse(String?.none) {
          End<Substring>()
        }
      }
    }

    while true {
      // Extract next variable if there is one
      let variable: String?
      do {
        let result = try parser.parse(&input)
        output += result.0
        variable = result.1
      } catch {
        throw Error(.unmatchedBrackets(string), cause: error)
      }

      guard let variable = variable else {
        break
      }

      // Evaluate variable value and append to output
      output += try await evaluateVariable(variable, with: evaluator)
    }

    return output
  }

  /// Evaluates the value of a variable.
  /// - Parameters:
  ///   - variable: The variable to evaluate.
  ///   - evaluator: The evaluator to use.
  /// - Returns: The variable's value.
  static func evaluateVariable(
    _ variable: String,
    with evaluator: Evaluator
  ) async throws(Error) -> String {
    switch evaluator {
      case .custom(let evaluator):
        do {
          return try evaluator(variable)
        } catch {
          throw Error(.customEvaluatorFailedToEvaluateVariable(variable), cause: error)
        }
      case .`default`(let context):
        return try await evaluateVariable(variable, with: context)
    }
  }

  /// The default variable value evaluator.
  /// - Parameters:
  ///   - variable: The variable to evaluate.
  ///   - context: The context required to evaluate variables.
  /// - Returns: The variable's value.
  static func evaluateVariable(  // swiftlint:disable:this cyclomatic_complexity
    _ variable: String,
    with context: Context
  ) async throws(Error) -> String {
    // TODO: Make text macros more generic
    let rfc1034Characters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890")
    let productRFC1034Identifier = String(
      context.productName.map { character in
        return rfc1034Characters.contains(character) ? character : "-"
      }
    )

    let value: String?
    switch variable {
      case "COMMIT_HASH":
        guard let packageDirectory = context.packageDirectory else {
          throw Error(.packageDirectoryRequiredToEvaluateCommitHash)
        }

        do {
          value = try await Git.getCommitHash(packageDirectory)
        } catch {
          throw Error(.failedToEvaluateCommitHash(directory: packageDirectory), cause: error)
        }
      case "REVISION_NUMBER":
        guard let packageDirectory = context.packageDirectory else {
          throw Error(.packageDirectoryRequiredToEvaluateRevisionNumber)
        }

        do {
          value = String(try await Git.countRevisions(packageDirectory))
        } catch {
          throw Error(.failedToEvaluateRevisionNumber(directory: packageDirectory), cause: error)
        }
      case "VERSION", "MARKETING_VERSION", "CURRENT_PROJECT_VERSION":
        value = context.version?.description
      case "PRODUCT_BUNDLE_IDENTIFIER":
        value = context.identifier
      case "PRODUCT_NAME":
        value = context.productName
      case "PRODUCT_NAME:rfc1034identifier":
        value = productRFC1034Identifier
      case "PRODUCT_BUNDLE_PACKAGE_TYPE":
        value = "APPL"
      case "DEVELOPMENT_LANGUAGE":
        value = "en"
      case "PRODUCT_MODULE_NAME":
        value = productRFC1034Identifier.replacingOccurrences(of: "-", with: "_")
      case "SRCROOT":
        value = "."  // Swift Bundler avoids using absolute paths
      case "UNIX_TIMESTAMP":
        value = String(context.date.timeIntervalSince1970)
      default:
        value = nil
    }

    guard let value = value else {
      throw Error(.unknownVariable(variable))
    }

    return value
  }

  /// Evaluates the expressions present in tree-like structure (only string
  /// values within the tree are evaluated).
  /// - Parameters:
  ///   - value: The value to evaluate.
  ///   - context: The context required to evaluate variables.
  /// - Returns: The evaluated value.
  static func evaluateVariables<Tree: VariableEvaluatable>(
    in value: Tree,
    with context: Context
  ) async throws(Error) -> Tree {
    do {
      if let stringValue = value.stringValue {
        let string = try await evaluateVariablesWorkaround(in: stringValue, with: context)
        return Tree.string(string)
      } else if let arrayValue = value.arrayValue {
        let array = try await evaluateVariablesWorkaround(in: arrayValue, with: context)
        return Tree.array(array)
      } else if let dictionaryValue = value.dictionaryValue {
        let dictionary = try await evaluateVariablesWorkaround(in: dictionaryValue, with: context)
        return Tree.dictionary(dictionary)
      } else {
        return value
      }
    } catch let error as Error {
      throw error
    } catch {
      throw Error(cause: error)
    }
  }

  /// Evaluates the variables present in an array of tree-like structures (only
  /// string values within the tree-like structures are evaluated).
  /// - Parameters:
  ///   - array: The array to evaluate.
  ///   - context: The context required to evaluate variables.
  /// - Returns: The evaluated array.
  static func evaluateVariables<Tree: VariableEvaluatable>(
    in array: [Tree],
    with context: Context
  ) async throws(Error) -> [Tree] {
    do {
      return try await evaluateVariablesWorkaround(in: array, with: context)
    } catch let error as Error {
      throw error
    } catch {
      throw Error(cause: error)
    }
  }

  /// See top of file for explanation.
  private static func evaluateVariablesWorkaround<Tree: VariableEvaluatable>(
    in array: [Tree],
    with context: Context
  ) async throws -> [Tree] {
    var evaluatedArray: [Tree] = []
    for value in array {
      let evaluatedValue = try await evaluateVariables(in: value, with: context)
      evaluatedArray.append(evaluatedValue)
    }
    return evaluatedArray
  }

  /// Evaluates the variables present in a map containing tree-like structures
  /// (only string values within the tree-like structures are evaluated).
  /// - Parameters:
  ///   - value: The dictionary to evaluate.
  ///   - context: The context required to evaluate variables.
  /// - Returns: The evaluated dictionary.
  static func evaluateVariables<Tree: VariableEvaluatable>(
    in dictionary: [String: Tree],
    with context: Context
  ) async throws(Error) -> [String: Tree] {
    do {
      return try await evaluateVariablesWorkaround(in: dictionary, with: context)
    } catch let error as Error {
      throw error
    } catch {
      throw Error(cause: error)
    }
  }

  /// See top of file for explanation.
  private static func evaluateVariablesWorkaround<Tree: VariableEvaluatable>(
    in dictionary: [String: Tree],
    with context: Context
  ) async throws -> [String: Tree] {
    var evaluatedDictionary: [String: Tree] = [:]
    for (key, value) in dictionary {
      let evaluatedValue = try await evaluateVariables(in: value, with: context)
      evaluatedDictionary[key] = evaluatedValue
    }
    return evaluatedDictionary
  }

  /// Evaluates the variables present in supported sections of an app
  /// configuration overlay.
  ///
  /// The only currently supported sections are ``AppConfiguration.Overlay/plist``
  /// and ``AppConfiguration.Overlay/metadata``.
  /// - Parameters:
  ///   - overlay: The configuration overlay to evaluate expressions in.
  ///   - context: The context required to evaluate variables.
  /// - Returns: The evaluated configuration overlay.
  static func evaluateVariables(
    in overlay: AppConfiguration.Overlay,
    with context: Context
  ) async throws(Error) -> AppConfiguration.Overlay {
    var overlay = overlay
    do {
      if let plist = overlay.plist {
        overlay.plist = try await evaluateVariablesWorkaround(in: plist, with: context)
      }
      if let metadata = overlay.metadata {
        overlay.metadata = try await evaluateVariablesWorkaround(in: metadata, with: context)
      }
    } catch let error as Error {
      throw error
    } catch {
      throw Error(cause: error)
    }
    return overlay
  }

  /// Evaluates the variables present in supported sections of an app's configuration.
  ///
  /// The only currently supported sections are ``AppConfiguration/plist``
  /// and ``AppConfiguration/metadata`` (and the equivalent sections within the
  /// configuration's overlays).
  /// - Parameters:
  ///   - configuration: The configuration to evaluate expressions in.
  ///   - appName: The app's name.
  ///   - packageDirectory: The package's root directory.
  /// - Returns: The evaluated configuration.
  static func evaluateVariables(
    in configuration: AppConfiguration,
    named appName: String,
    packageDirectory: URL
  ) async throws(Error) -> AppConfiguration {
    let context = Context(
      appName: appName,
      productName: configuration.product,
      date: Date(),
      packageDirectory: packageDirectory,
      version: configuration.version,
      identifier: configuration.identifier
    )

    var configuration = configuration
    do {
      if let plist = configuration.plist {
        configuration.plist = try await evaluateVariablesWorkaround(in: plist, with: context)
      }
      if let metadata = configuration.metadata {
        configuration.metadata = try await evaluateVariablesWorkaround(in: metadata, with: context)
      }
      if let overlays = configuration.overlays {
        configuration.overlays = try await overlays.typedAsyncMap {
          (overlay) throws(Error) -> AppConfiguration.Overlay in
          try await evaluateVariables(in: overlay, with: context)
        }
      }
    } catch let error as Error {
      throw error
    } catch {
      throw Error(cause: error)
    }
    return configuration
  }

  /// Evaluates the variables present in supported sections of a package's configuration.
  ///
  /// The only currently supported section in ``AppConfiguration/plist``.
  /// - Parameters:
  ///   - configuration: The configuration to evaluate expressions in.
  ///   - packageDirectory: The package's root directory (used to evaluate certain variables).
  /// - Returns: The evaluated configuration.
  static func evaluateVariables(
    in configuration: PackageConfiguration,
    packageDirectory: URL
  ) async throws(Error) -> PackageConfiguration {
    var evaluatedConfiguration = configuration
    for (name, app) in configuration.apps {
      evaluatedConfiguration.apps[name] = try await evaluateVariables(
        in: app,
        named: name,
        packageDirectory: packageDirectory
      )
    }
    return evaluatedConfiguration
  }
}
