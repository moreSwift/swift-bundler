import Foundation

#if os(macOS)
  import ConcurrencyExtras
#endif

// Source: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0417-task-executor-preference.md#combining-serialexecutor-and-taskexecutor
@available(macOS 15, *)
private final class NaiveQueueExecutor: TaskExecutor, SerialExecutor {
  let queue: DispatchQueue

  init(_ queue: DispatchQueue) {
    self.queue = queue
  }

  func enqueue(_ job: consuming ExecutorJob) {
    let unownedJob = UnownedJob(job)
    queue.async {
      unownedJob.runSynchronously(
        isolatedTo: self.asUnownedSerialExecutor(),
        taskExecutor: self.asUnownedTaskExecutor()
      )
    }
  }

  @inlinable
  public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
    UnownedSerialExecutor(ordinary: self)
  }

  @inlinable
  public func asUnownedTaskExecutor() -> UnownedTaskExecutor {
    UnownedTaskExecutor(ordinary: self)
  }
}

/// Runs the given operation on a serial task executor.
///
/// NOTE: If this function fails to compile, try using a newer Swift version.
///   Swift 6.1 is known to fail on macOS, but we haven't bumped the overall
///   package Swift tools version because we don't want the tests to dictate
///   our supported Swift versions (given that tests don't affect consumers)
func withSerialTaskExecutor<T, Failure: Error>(
  isolation: isolated (any Actor)? = #isolation,
  queueLabel: String = #function,
  operation: () async throws(Failure) -> T
) async throws(Failure) -> T {
  if #available(macOS 15, *) {
    let queue = DispatchQueue(label: queueLabel)
    let executor = NaiveQueueExecutor(queue)
    return try await withTaskExecutorPreference(
      executor,
      isolation: isolation,
      operation: operation
    )
  } else {
    #if os(macOS)
      // This is a fallback for older versions of macOS. The downside of this
      // approach is that it affects every other test running in parallel for the
      // duration of the operation because it overrides swift_task_enqueueGlobal_hook 
      // to control task execution
      let didUseMainSerialExecutor = ConcurrencyExtras.uncheckedUseMainSerialExecutor
      defer {
        ConcurrencyExtras.uncheckedUseMainSerialExecutor = didUseMainSerialExecutor
      }
      ConcurrencyExtras.uncheckedUseMainSerialExecutor = true
      return try await operation()
    #else
      fatalError("How did we get here?")
    #endif
  }
}
