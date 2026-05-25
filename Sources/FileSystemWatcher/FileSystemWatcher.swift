#if canImport(Inotify)
  import Inotify
  import AsyncAlgorithms
  import struct SystemPackage.FilePath
#endif

public enum FileSystemWatcher {
  public static func watch(
    paths: [String],
    with handler: @escaping @Sendable () -> Void,
    errorHandler: @escaping @Sendable (any Swift.Error) -> Void
  ) async throws {
    #if canImport(CoreServices)
      // TODO: Maybe update to use async/await?
      try CoreServicesFileSystemWatcher.startWatchingForDebouncedModifications(
        paths: paths,
        with: handler,
        errorHandler: errorHandler
      )
    #elseif canImport(Inotify)
      let notifier = try Inotifier()
      try await Task {
        try await withThrowingTaskGroup(of: Void.self) { group in
          for path in paths {
            do {
              let stream = try await notifier.events(for: FilePath(path))
              group.addTask {
                // let filteredStream = stream.filter { event in
                //   let result = !event.flags.intersection([
                //     .fileCreated, .fileDeleted, .modified, .movedFrom, .movedTo,
                //     .selfDeleted, .selfMoved, .writableFileClosed,
                //   ]).isEmpty
                //   print("Got event \(event.flags): \(result)")
                //   return result
                // }

                for await event in stream.debounce(for: .milliseconds(100)) {
                  print("Handling \(event.path)")
                  handler()
                }
              }
            } catch {
              errorHandler(error)
              return
            }
          }

          try await group.waitForAll()
        }
      }.value
    #else
      #error("File system watching not implemented for current platform")
    #endif
  }
}
