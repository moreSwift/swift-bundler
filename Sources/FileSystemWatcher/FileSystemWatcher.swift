import Foundation

#if canImport(Inotify)
  import Inotify
  import AsyncAlgorithms
  import struct SystemPackage.FilePath
  import Mutex
#endif

public enum FileSystemWatcher {
  /// Recursively watches a directory for changes.
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
      let newDirectories = AsyncChannel<String>()
      let eventChannel = AsyncChannel<Void>()
      let eventStream = AsyncStream { continuation in
        let task = Task {
          for await element in eventChannel {
            continuation.yield(element)
          }
          continuation.finish()
        }
        
        continuation.onTermination = { @Sendable _ in
          task.cancel()
        }
      }

      try await Task {
        try await withThrowingTaskGroup(of: Void.self) { group in
          // inotify doesn't support recursive directory observation, which
          // introduces a bit more complexity for us
          let recursivePaths = recursivelyEnumerateDirectories(in: paths)

          let watchedPaths = Mutex(recursivePaths)

          @Sendable func handleEvent() async {
            // Check for newly created subdirectories
            watchedPaths.withLock { watchedPaths in
              let recursivePaths = recursivelyEnumerateDirectories(in: paths)

              for path in recursivePaths {
                guard !watchedPaths.contains(path) else { continue }
                Task {
                  await newDirectories.send(path)
                }
              }

              // We may end up watching directories twice when they get moved, but
              // it shouldn't affect us much because of our debouncing. The reason
              // that we completely override the watchedPaths is that when a directory
              // gets deleted, our corresponding watch gets removed, so if a directory
              // appears at the same place in future we have to re-watch it.
              watchedPaths = recursivePaths
            }

            handler()
          }

          group.addTask { @Sendable in
            // Handle events (debounced to avoid duplicate updates when hot reloading)
            for await _ in eventStream.debounce(for: .milliseconds(100)) {
              await handleEvent()
            }
          }

          for path in recursivePaths {
            group.addTask { @Sendable in
              await watchSinglePath(
                path: path,
                with: notifier,
                eventChannel: eventChannel,
                errorHandler: errorHandler
              )
            }
          }

          // Watch new directories as we discover them
          for await directory in newDirectories {
            group.addTask { @Sendable in
              await watchSinglePath(
                path: directory,
                with: notifier,
                eventChannel: eventChannel,
                errorHandler: errorHandler
              )
            }
          }

          try await group.waitForAll()
        }
      }.value
    #else
      #error("File system watching not implemented for current platform")
    #endif
  }

  #if canImport(Inotify)
    /// Watches a single directory for changes, non-recursively.
    private static func watchSinglePath(
      path: String,
      with notifier: Inotifier,
      eventChannel: AsyncChannel<()>,
      errorHandler: @escaping @Sendable (any Swift.Error) -> Void
    ) async {
      do {
        let stream = try await notifier.events(for: FilePath(path))
        let filteredStream = stream.filter { event in
          return !event.flags.intersection([
            .fileCreated, .fileDeleted, .modified, .movedFrom, .movedTo,
            .selfDeleted, .selfMoved, .writableFileClosed,
          ]).isEmpty
        }

        for await _ in filteredStream {
          await eventChannel.send(())
        }
      } catch {
        errorHandler(error)
      }
    }

    /// Enumerates all subdirectories contained within the set of given directories,
    /// including the directories themselves.
    private static func recursivelyEnumerateDirectories(in directories: [String]) -> [String] {
      var recursivePaths: [String] = []
      for path in directories {
        guard let enumerator = FileManager.default.enumerator(
          at: URL(fileURLWithPath: path),
          includingPropertiesForKeys: nil
        ) else {
          print("warning: Could not enumerate directory at path '\(path)'")
          continue
        }

        recursivePaths.append(path)

        for file in enumerator {
          guard
            let file = file as? URL,
            file.hasDirectoryPath
          else {
            continue
          }

          if !recursivePaths.contains(file.path) {
            recursivePaths.append(file.path)
          }
        }
      }
      return recursivePaths
    }
  #endif
}
