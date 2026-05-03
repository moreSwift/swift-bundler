import Foundation

/// A project builder.
public protocol Builder {
  /// Builds the project defined by the given context.
  static func build(_ context: some BuilderContext) async throws -> BuilderResult
}

private enum BuilderError: LocalizedError {
  case noInput

  var errorDescription: String? {
    switch self {
      case .noInput:
        return "No input provided to builder (expected JSON object on stdin)"
    }
  }
}

extension Builder {
  /// Default builder entrypoint. Parses builder context from stdin.
  public static func main() async {
    do {
      let input = try await readLineAsync()

      let context = try JSONDecoder().decode(
        _BuilderContextImpl.self, from: Data(input.utf8)
      )

      _ = try await build(context)
    } catch {
      print(error)
      Foundation.exit(1)
    }
  }
}

func readLineAsync(strippingNewline: Bool = true) async throws -> String {
  let readBytesStream = AsyncStream.makeStream(of: Data.self)

  FileHandle.standardInput.readabilityHandler = { handle in
    readBytesStream.continuation.yield(handle.availableData)
  }

  defer { FileHandle.standardInput.readabilityHandler = nil }

  var accumulatedData = Data()
  for await data in readBytesStream.stream {
    accumulatedData.append(data)
    if let stringData = String(data: accumulatedData, encoding: .utf8),
      stringData.contains(where: \.isNewline),
      let firstLine = stringData.components(separatedBy: .newlines).first
    {
      readBytesStream.continuation.finish()
      if strippingNewline {
        return firstLine
      } else {
        return firstLine + "\n"
      }
    }
  }

  throw BuilderError.noInput
}
