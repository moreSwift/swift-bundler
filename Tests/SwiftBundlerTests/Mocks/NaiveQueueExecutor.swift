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

  func enqueue(_ _job: consuming ExecutorJob) {
    let job = UnownedJob(_job)
    queue.async {
      job.runSynchronously(
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
  }
}
