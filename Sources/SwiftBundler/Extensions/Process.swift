import Foundation
import Mutex

#if os(Linux)
  import Glibc
  import ProcessSpawnSync
  public typealias Process = PSProcess
#endif

#if canImport(Darwin)
  /// A pipe used to suppress process output. By using this for output suppression,
  /// we can tell when it's safe for us to drain the pipe on the caller's behalf and
  /// when it's not.
  ///
  /// Pipe is an abstract obj-c class (a class cluster) so we have to manually
  /// implement Pipe's abstract requirements by calling the respective requirements
  /// on a concrete Pipe. When you initialize a Pipe, its actual type is
  /// NSConcretePipe. If NSConcretePipe was public then we could just subclass that
  /// directly, but it's not.
  private class SuppressionPipe: Pipe, @unchecked Sendable {
    let pipe = Pipe()

    override var fileHandleForReading: FileHandle {
      pipe.fileHandleForReading
    }

    override var fileHandleForWriting: FileHandle {
      pipe.fileHandleForWriting
    }
  }
#else
  private class SuppressionPipe: Pipe, @unchecked Sendable {}
#endif

extension Process {
  /// All processes that have been created using `Process.create(_:arguments:directory:pipe:)`.
  ///
  /// If the program is killed, all processes in this array are terminated before the program exits.
  static var processes: Mutex<[Process]> = Mutex([])

  #if os(Linux)
    /// The PIDs of all AppImage processes started manually (due to the weird
    /// workaround required).
    static var appImagePIDs: [pid_t] = []
  #endif

  /// Kill all running processes on exit
  public static func killAllRunningProcessesOnExit() {
    for signal in Signal.allCases {
      trap(signal) {
        Process.processes.withLock { processes in
          for process in processes {
            if process.isRunning {
              process.terminate()
            }
          }
        }
        #if os(Linux)
          for pid in Process.appImagePIDs {
            kill(pid, SIGKILL)
          }
        #endif
        Foundation.exit(1)
      }
    }
  }

  /// A string representation of the command, suitable only for logging (not running).
  /// Doesn't guarantee that the produced representation is faithful, but does strive
  /// to improve in that respect over time.
  var commandString: String {
    CommandLine(
      command: executableURL?.path ?? "<unknown>",
      arguments: arguments ?? []
    ).description
  }

  /// Sets the pipe for the process's stdout and stderr.
  /// - Parameter excludeStdError: If `true`, only stdout is piped.
  /// - Parameter pipe: The pipe.
  func setOutputPipe(_ pipe: Pipe, excludeStdError: Bool = false) {
    standardOutput = pipe
    if !excludeStdError {
      standardError = pipe
    }
  }

  private static func getOutputData(
    from pipe: Pipe,
    whilePerforming action: () async throws(Error) -> Void
  ) async throws(Error) -> Data {
    // Thanks Martin! https://forums.swift.org/t/the-problem-with-a-frozen-process-in-swift-process-class/39579/6

    let dataStream = AsyncStream.makeStream(of: Data.self)

    let handleDataTask = Task<Data, any Swift.Error> {
      var output = Data()

      for await data in dataStream.stream {
        output.append(contentsOf: data)
      }

      if #available(macOS 10.15.4, *) {
        if let data = try pipe.fileHandleForReading.readToEnd() {
          output.append(contentsOf: data)
        }
      }

      return output
    }

    let disableReadabilityHandler = Mutex(false)

    // We assume that our readabilityHandler never gets called concurrently. If
    // it does we'd likely have to record the number of in-flight handlers in an
    // atomic instead.
    pipe.fileHandleForReading.readabilityHandler = { fileHandle in
      disableReadabilityHandler.withLock { disable in
        // Sometimes on Linux, our readabilityHandler gets called after the
        // termination handler, even once we've set pipe.fileHandlerForReading.readabilityHandler
        // to nil... We guard against that with this flag. If we instead just let the handler run,
        // then we end up reading `availableData` before or during `readToEnd` in `handleDataTask`
        // which leads to `readToEnd` returning no data.
        guard !disable else {
          return
        }

        let data = fileHandle.availableData
        dataStream.continuation.yield(data)
      }
    }

    // Closes the output pipe and waits for the data stream to finish
    // processing.
    let finalize: () async throws(Error) -> Data = {
      try? pipe.fileHandleForWriting.close()

      pipe.fileHandleForReading.readabilityHandler = nil

      // Sometimes on Linux, availableData blocks until after the termination
      // handler gets called, which then causes us to yield the data into a
      // finalised stream (and losing it to the void). This mutex helps fix this
      // because it'll block us until any existing handler invocation completes.
      // We then set the disabled flag to true so that any future invocations exit
      // early before reading availableData.
      disableReadabilityHandler.withLock { disable in
        disable = true
      }

      dataStream.continuation.finish()
      return try await Error.catch {
        try await handleDataTask.value
      }
    }

    let output: Data
    do {
      try await action()
      output = try await finalize()
    } catch {
      switch error.message {
        case .nonZeroExitStatus(let command, let status):
          // We try finalize again here because we know that finalize doesn't throw
          // the nonZeroExitStatus error, so we mustn't have reached finalize in the do
          // block before throwing.
          throw Error(.nonZeroExitStatusWithOutput(try await finalize(), command, status))
        default:
          throw error
      }
    }

    return output
  }

  /// Gets the process's stdout and stderr as `Data`.
  /// - Parameters:
  ///   - excludeStdError: If `true`, only stdout is returned.
  /// - Returns: The process's stdout and stderr.
  func getOutputData(excludeStdError: Bool = false) async throws(Error) -> Data {
    let pipe = Pipe()
    setOutputPipe(pipe, excludeStdError: excludeStdError)

    return try await Self.getOutputData(from: pipe) { () async throws(Error) in
      try await runAndWait()
    }
  }

  /// Gets the process's stdout and stderr as a string.
  /// - Parameter excludeStdError: If `true`, only stdout is returned.
  /// - Returns: The process's stdout and stderr.
  func getOutput(excludeStdError: Bool = false) async throws(Error) -> String {
    let data = try await getOutputData(excludeStdError: excludeStdError)
    guard let output = String(data: data, encoding: .utf8) else {
      throw Error(.invalidUTF8Output(output: data))
    }

    return output
  }

  /// Runs the process and waits for it to complete.
  /// - Throws: An error if the process has a non-zero exit status of fails to run.
  func runAndWait() async throws(Error) {
    func body() async throws(Error) {
      do {
        try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Void, Swift.Error>) in
          terminationHandler = { _ in
            continuation.resume()
          }

          do {
            try runAndLog()
          } catch {
            continuation.resume(throwing: error)
          }
        }
      } catch {
        throw Error(.failedToRunProcess, cause: error)
      }

      let exitStatus = Int(terminationStatus)
      guard exitStatus == 0 else {
        throw Error(.nonZeroExitStatus(commandString, exitStatus))
      }
    }

    if let pipe = standardOutput as? SuppressionPipe {
      _ = try await Self.getOutputData(from: pipe, whilePerforming: body)
    } else {
      try await body()
    }
  }

  func runAndLog() throws {
    log.debug(
      """
      Running command: '\(executableURL?.path ?? "")' with arguments: \
      \(arguments ?? []), working directory: \
      \(currentDirectoryURL?.path ?? FileManager.default.currentDirectoryPath)
      """
    )

    try run()
  }

  /// Adds environment variables to the process's environment.
  /// - Parameter variables: The key value pairs to add.
  func addEnvironmentVariables(_ variables: [String: String]) {
    var environment = environment ?? ProcessInfo.processInfo.environment
    for (key, value) in variables {
      environment[key] = value
    }
    self.environment = environment
  }

  /// Creates a new process (but doesn't run it).
  /// - Parameters:
  ///   - tool: The tool.
  ///   - arguments: The tool's arguments.
  ///   - directory: The directory to run the command in. Defaults to the current
  ///     directory.
  ///   - pipe: The pipe for the process's stdout and stderr. Defaults to `nil`.
  ///   - runSilentlyWhenNotVerbose: If `true`, output is captured even when no
  ///     pipe is provided id Swift Bundler wasn't run with `-v`. Defaults to
  ///     `true`.
  /// - Returns: The new process.
  static func create(
    _ tool: String,
    arguments: [String] = [],
    environment: [String: String] = [:],
    directory: URL? = nil,
    pipe: Pipe? = nil,
    runSilentlyWhenNotVerbose: Bool = true
  ) -> Process {
    let process = Process()

    if let pipe {
      process.setOutputPipe(pipe)
    } else if log.logLevel == .info && runSilentlyWhenNotVerbose {
      // Silence standard error and output by default when not verbose.
      let pipe = SuppressionPipe()
      process.standardOutput = pipe
      process.standardError = pipe
    }

    process.currentDirectoryURL = directory?.standardizedFileURL.absoluteURL

    // If tool isn't a path, assume it's on the user's PATH
    if tool.hasPrefix("/") || tool.hasPrefix("./") {
      process.executableURL = URL(fileURLWithPath: tool)
      process.arguments = arguments
    } else {
      switch HostPlatform.hostPlatform {
        case .linux, .macOS:
          process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
          process.arguments = [tool] + arguments
        case .windows:
          process.executableURL = URL(fileURLWithPath: "C:\\Windows\\System32\\cmd.exe")
          process.arguments = ["/c", tool] + arguments
      }
    }

    var env = ProcessInfo.processInfo.environment
    if env.keys.contains("OS_ACTIVITY_DT_MODE") {
      // Fix an issue to do with Xcode breaking SwiftPackageManager
      // (https://stackoverflow.com/a/67613515)
      env["OS_ACTIVITY_DT_MODE"] = nil
    }
    for (key, value) in environment {
      env[key] = value
    }
    process.environment = env

    processes.withLock { processes in
      processes.append(process)
    }

    return process
  }

  /// Gets the full path to the specified tool (using the `which` shell command). If
  /// you don't need to explicitly know the path from Swift, just pass the name of the
  /// tool to `Process.create` instead (which will detect that it's not a path and instead
  /// run the tool through `/usr/bin/env` which will find the tool on the user's `PATH`).
  /// - Parameter tool: The tool to expand into a full path.
  /// - Returns: The absolute path to the tool.
  static func locate(_ tool: String) async throws(Error) -> String {
    // Restrict the set of inputs to avoid command injection. This is very dodgy but there
    // doesn't seem to be any nice way to call bash built-ins directly with an argument
    // vector. Better approaches are extremely welcome!!
    guard
      tool.allSatisfy({ character in
        character.isASCII
          && (character.isLetter
            || character.isNumber || character == "-" || character == "_")
      })
    else {
      throw Error(.invalidToolName(tool))
    }

    do {
      let path = try await Process.create(
        "/bin/sh",
        arguments: [
          "-c",
          "which \(tool)",
        ],
        runSilentlyWhenNotVerbose: false
      ).getOutput()

      return path.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      throw Error(.failedToLocateTool(tool), cause: error)
    }
  }

  /// Runs an app image. For some reason ``Foundation/Process`` can't handle
  /// app images. It just keeps waiting indefinitely even once the process
  /// has clearly finished. It also can't terminate them. App images probably
  /// just do some weird forking or something, but doing the process management
  /// ourselves seems to fix the issues.
  ///
  /// The issue occurs even without any pipes attached, so it's not the classic
  /// full pipes issue.
  static func runAppImage(
    _ appImage: String,
    arguments: [String],
    additionalEnvironmentVariables: [String: String] = [:]
  ) async throws(Error) {
    #if os(Linux)
      var environment = ProcessInfo.processInfo.environment
      for (key, value) in additionalEnvironmentVariables {
        guard isValidEnvironmentVariableKey(key) else {
          throw Error(.invalidEnvironmentVariableKey(key))
        }
        environment[key] = value
      }

      let environmentArray =
        environment.map { key, value in
          strdup("\(key)=\(value)")
        } + [UnsafeMutablePointer<CChar>(bitPattern: 0)]

      // Locate the tool or interpret it as a relative/absolute path.
      let executablePath: String
      do {
        executablePath = try await locate(appImage)
      } catch {
        if case .invalidToolName = error.message {
          executablePath = appImage
        } else {
          throw error
        }
      }

      let cArguments =
        ([executablePath] + arguments).map { strdup($0) }
        + [UnsafeMutablePointer<CChar>(bitPattern: 0)]

      let selfPID = getpid()
      setpgid(0, selfPID)
      let childPID = fork()
      if childPID == 0 {
        setpgid(0, selfPID)
        execve(executablePath, cArguments, environmentArray)
        // We only ever get here if the execv fails
        Foundation.exit(-1)
      } else {
        appImagePIDs.append(childPID)
        var status: Int32 = 0
        waitpid(childPID, &status, 0)
        if status != 0 {
          let commandString = CommandLine(
            command: executablePath,
            arguments: arguments
          ).description
          throw Error(.nonZeroExitStatus(commandString, Int(status)))
        } else {
          return
        }
      }
    #else
      let process = Process.create(
        appImage,
        arguments: arguments,
        runSilentlyWhenNotVerbose: false
      )

      try await process.runAndWait()
    #endif
  }

  /// Validates an environment variable key. Currently only used by a Linux workaround
  /// that has to interface with low-level APIs.
  private static func isValidEnvironmentVariableKey(_ key: String) -> Bool {
    key.allSatisfy({ character in
      character.isASCII
        && (character.isLetter || character.isNumber || character == "_")
    }) && key.first?.isNumber == false
  }
}
