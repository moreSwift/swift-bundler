extension Result {
  /// Creates a Result from an asynchronous action.
  static func catching(_ action: () async throws(Failure) -> Success) async -> Self {
    do {
      let result = try await action()
      return .success(result)
    } catch {
      return .failure(error)
    }
  }
}
