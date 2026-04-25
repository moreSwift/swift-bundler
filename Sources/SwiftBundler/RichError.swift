import ErrorKit
import Foundation
import Rainbow

/// A simple error consisting of a single string description.
struct StringError: Throwable {
  var userFriendlyMessage: String
}

/// The location in the codebase. Used to track error origination.
struct Location: CustomStringConvertible {
  var file: String
  var line: Int
  var column: Int

  var description: String {
    "\(URL(fileURLWithPath: file).lastPathComponent):\(line):\(column)"
  }
}

/// A rich error. Provides a chain of blame without requiring additional
/// cumbersome `caught` enum cases.
struct RichError<Message: Error>: Throwable, RichErrorProtocol {
  var message: Message?
  var cause: (any Error)?
  var hint: String?
  var location: Location

  var erasedMessage: (any Error)? {
    message
  }

  var messageType: any Error.Type {
    Message.self
  }

  /// Creates a rich error from a message and an optional underlying cause.
  init(
    _ message: Message,
    cause: (any Error)? = nil,
    hint: String? = nil,
    file: String = #file,
    line: Int = #line,
    column: Int = #column
  ) {
    self.message = message
    self.cause = cause
    self.hint = hint
    self.location = Location(file: file, line: line, column: column)
  }

  /// Creates a rich error with an underlying cause but no message.
  init(
    cause: any Error,
    hint: String? = nil,
    file: String = #file,
    line: Int = #line,
    column: Int = #column
  ) {
    self.message = nil
    self.cause = cause
    self.hint = hint
    self.location = Location(file: file, line: line, column: column)
  }

  /// Creates a rich error from an optional message and an underlying cause.
  /// This is sometimes convenient, but causes overload ambiguity so it's
  /// a disfavored overload.
  @_disfavoredOverload
  init(
    _ message: Message?,
    cause: any Error,
    hint: String? = nil,
    file: String = #file,
    line: Int = #line,
    column: Int = #column
  ) {
    self.message = message
    self.cause = cause
    self.hint = hint
    self.location = Location(file: file, line: line, column: column)
  }

  static func `catch`<R>(
    withMessage message: Message? = nil,
    do body: () throws -> R,
    file: String = #file,
    line: Int = #line,
    column: Int = #column
  ) throws(Self) -> R {
    do {
      return try body()
    } catch {
      if message == nil, let error = error as? Message {
        throw Self(error, file: file, line: line, column: column)
      } else if let message {
        throw Self(message, cause: error, file: file, line: line, column: column)
      } else {
        throw Self(cause: error, file: file, line: line, column: column)
      }
    }
  }

  static func `catch`<R>(
    withMessage message: Message? = nil,
    do body: () async throws -> R,
    file: String = #file,
    line: Int = #line,
    column: Int = #column
  ) async throws(Self) -> R {
    do {
      return try await body()
    } catch {
      if message == nil, let error = error as? Message {
        throw Self(error, file: file, line: line, column: column)
      } else if let message {
        throw Self(message, cause: error, file: file, line: line, column: column)
      } else {
        throw Self(cause: error, file: file, line: line, column: column)
      }
    }
  }

  var userFriendlyMessage: String {
    if let message {
      return ErrorKit.userFriendlyMessage(for: message)
    } else if let cause {
      return ErrorKit.userFriendlyMessage(for: cause)
    } else {
      // Unlikely to reach unless the user manually sets the message or cause to
      // nil after using one of the two available initializers.
      return "\(Message.self)"
    }
  }
}

extension Throwable {
  func becauseOf(_ error: any Error) -> RichError<Self> {
    RichError(self, cause: error)
  }
}

extension RichError where Message == StringError {
  /// Creates a rich error from a string description and an optional underlying
  /// cause.
  init(
    _ message: String,
    cause: (any Error)? = nil,
    file: String = #file,
    line: Int = #line,
    column: Int = #column
  ) {
    self.message = StringError(userFriendlyMessage: message)
    self.cause = cause
    self.location = Location(file: file, line: line, column: column)
  }
}

extension RichError {
  private static func initHelper<T: Error>(_ existingCause: T, cause: any Error) -> RichError<T> {
    RichError<T>(existingCause, cause: cause)
  }

  func becauseOf(_ cause: any Error) -> Self {
    var richError = self
    if let existingCause = richError.cause {
      richError.cause = Self.initHelper(existingCause, cause: cause)
    } else {
      richError.cause = cause
    }
    return richError
  }
}

protocol RichErrorProtocol: Throwable {
  var erasedMessage: (any Error)? { get }
  var messageType: any Error.Type { get }
  var cause: (any Error)? { get }
  var hint: String? { get }
  var location: Location { get }
}

func location(of error: Error) -> Location? {
  (error as? RichErrorProtocol)?.location
}

/// Produces a nicer debug description of a value. At the moment the main
/// things that it does are printing URLs and errors nicer.
private func niceDebugDescription(of value: Any) -> String {
  let typeName = "\(type(of: value))"
  let isTuple = typeName.hasPrefix("(") && typeName != "().self"
  if isTuple {
    let mirror = Mirror(reflecting: value)
    let values = mirror.children.map(\.value)
    let descriptions = values.map(niceDebugDescription(of:))
    let labels: [String] = mirror.children.map(\.label).compactMap { label in
      if label?.hasPrefix(".") != false {
        return nil
      } else {
        return label
      }
    }
    if labels.count == descriptions.count {
      return "(\(zip(labels, descriptions).map { "\($0): \($1)" }.joined(separator: ", ")))"
    } else {
      return "(\(descriptions.joined(separator: ", ")))"
    }
  } else if let url = value as? URL {
    return String(reflecting: url.path(relativeTo: URL.currentDirectory))
  } else if let error = value as? any Error {
    return String(reflecting: ErrorKit.userFriendlyMessage(for: error))
  } else {
    return String(reflecting: value)
  }
}

/// Produces a description for an enum's associated value (a single value or
/// tuple). Ensures the value gets surrounded with brackets.
private func enumAssociatedValueDescription(value: Any) -> String {
  let description = niceDebugDescription(of: value)
  // Surround with parentheses
  if !description.hasPrefix("(") {
    return "(\(description))"
  } else {
    return description
  }
}

/// Custom error debug printing logic. The main thing it does is print URLs a
/// bit more nicely.
private func errorDebugDescription(_ error: (any Error)?, type: any Error.Type) -> String {
  // TODO: Handle structs.
  let typeName = String(reflecting: type)

  if let error {
    let mirror = Mirror(reflecting: error)
    if mirror.displayStyle == .enum {
      let caseName = mirror.children.first?.label ?? String(describing: error)
      let value = (mirror.children.first?.value).map { value in
        enumAssociatedValueDescription(value: value)
      } ?? ""
      return "\(typeName).\(caseName)\(value)"
    } else {
      // TODO: Give structs and classes a similar treatment eventually
      return String(reflecting: error)
    }
  } else {
    return "\(typeName)"
  }
}

private func inlineErrorDescription(for error: any Error, verbose: Bool) -> String {
  let errorDescription: String
  if verbose {
    if let message = (error as? RichErrorProtocol)?.erasedMessage {
      errorDescription = errorDebugDescription(message, type: type(of: message))
    } else {
      errorDescription = errorDebugDescription(error, type: type(of: error))
    }
  } else {
    errorDescription = ""
  }

  let locationDescription: String
  if verbose, let location = location(of: error) {
    locationDescription = " at \(location)"
  } else {
    locationDescription = ""
  }

  var description = ErrorKit.userFriendlyMessage(for: error)
  if verbose {
    description += " (\(errorDescription)\(locationDescription))"
  }
  return description
}

/// Produces a description of an error, using RichError chaining to include
/// underlying causes where possible. Output may be multiline.
func chainDescription(for error: any Error, verbose: Bool) -> String {
  if var error = error as? RichErrorProtocol {
    while error.erasedMessage == nil {
      guard let cause = error.cause as? RichErrorProtocol else {
        return inlineErrorDescription(for: error, verbose: verbose)
      }
      error = cause
    }

    var output = inlineErrorDescription(for: error, verbose: verbose)

    var cause = error.cause
    while let currentCause = cause {
      if !(currentCause is RichErrorProtocol)
        || (currentCause as? RichErrorProtocol)?.erasedMessage != nil
      {
        var message = ErrorKit.userFriendlyMessage(for: currentCause)
        if message.isEmpty {
          message = currentCause.localizedDescription
        }

        let locationString: String
        if verbose, let location = location(of: currentCause) {
          locationString = " error at \(location)"
        } else {
          locationString = ""
        }

        let errorDescription: String
        if verbose {
          let message = if let currentCause = currentCause as? RichErrorProtocol {
            currentCause.erasedMessage
          } else {
            currentCause
          }

          if let message {
            errorDescription = " " + errorDebugDescription(message, type: type(of: message))
          } else {
            errorDescription = ""
          }
        } else {
          errorDescription = ""
        }

        output += """


          Caused by\(locationString):\(errorDescription)
            \(message.split(separator: "\n").joined(separator: "\n  "))
          """
      }

      if let currentCause = currentCause as? RichErrorProtocol {
        cause = currentCause.cause
      } else {
        break
      }
    }

    return output
  } else {
    return inlineErrorDescription(for: error, verbose: verbose)
  }
}

func hints(containedIn error: any Error) -> [String] {
  var currentError = error
  var hints: [String] = []
  while let richError = currentError as? RichErrorProtocol {
    if let hint = richError.hint {
      hints.append(hint)
    }

    guard let nextError = richError.cause else {
      break
    }
    currentError = nextError
  }
  return hints
}

func displayError(_ error: any Error, verbose: Bool, displayHints: Bool) {
  log.error("\(chainDescription(for: error, verbose: verbose))")
  let hints = hints(containedIn: error)
  for hint in hints {
    log.info("\(hint)")
  }
}
