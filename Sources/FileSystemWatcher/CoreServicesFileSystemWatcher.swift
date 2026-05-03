// This is a modified and cleaned up version of eonil's FSEvents package. All credit goes to eonil: https://github.com/eonil/FSEvents/

#if canImport(CoreServices)
  import Foundation
  import CoreServices

  struct CoreServicesFileSystemWatcher {
    private final class Debouncer: @unchecked Sendable {
      var latestEvent: CoreServicesFileSystemWatcher.EventID? = nil
    }

    fileprivate actor StreamHolder {
      var streams: [CoreServicesFileSystemWatcher.EventStream] = []

      func add(_ stream: CoreServicesFileSystemWatcher.EventStream) {
        streams.append(stream)
      }
    }

    /// Used to keep strong references to streams.
    private static let streams = StreamHolder()

    static func startWatching(
      paths: [String],
      with handler: @escaping @Sendable (CoreServicesFileSystemWatcher.Event) -> Void,
      errorHandler: @escaping @Sendable (Swift.Error) -> Void
    ) throws {
      try DispatchQueue.runOnMainThread {
        let stream = try EventStream(
          pathsToWatch: paths,
          sinceWhen: .now,
          latency: 0.5,
          flags: [.noDefer, .fileEvents],
          handler: handler,
          errorHandler: errorHandler
        )

        stream.setDispatchQueue(DispatchQueue.main)
        try stream.start()

        Task {
          await streams.add(stream)
        }
      }
    }

    static func startWatchingForDebouncedModifications(
      paths: [String],
      with handler: @escaping @Sendable () -> Void,
      errorHandler: @escaping @Sendable (Swift.Error) -> Void
    ) throws {
      let debouncer = Debouncer()

      let queue = DispatchQueue(label: "debounced-event-handler")

      try startWatching(
        paths: paths,
        with: { event in
          // Only handle modification events
          if event.flags?.contains(.itemCloned) == true
            || event.flags?.contains(.historyDone) == true
          {
            return
          }

          // Store the latest event id and then wait 200 milliseconds to debounce
          queue.sync {
            debouncer.latestEvent = event.id
          }

          queue.asyncAfter(deadline: .now() + .milliseconds(200)) {
            if debouncer.latestEvent == event.id {
              handler()
            }
          }
        },
        errorHandler: errorHandler
      )
    }
  }

  extension CoreServicesFileSystemWatcher {
    struct CreateFlags: OptionSet, Hashable {
      let rawValue: FSEventStreamCreateFlags

      init(rawValue: FSEventStreamCreateFlags) {
        self.rawValue = rawValue
      }

      init(rawValue: Int) {
        self.rawValue = FSEventStreamCreateFlags(truncatingIfNeeded: rawValue)
      }

      static var none: CreateFlags {
        return CreateFlags(rawValue: kFSEventStreamCreateFlagNone)
      }

      static var useCFTypes: CreateFlags {
        return CreateFlags(rawValue: kFSEventStreamCreateFlagUseCFTypes)
      }

      static var noDefer: CreateFlags {
        return CreateFlags(rawValue: kFSEventStreamCreateFlagNoDefer)
      }

      static var watchRoot: CreateFlags {
        return CreateFlags(rawValue: kFSEventStreamCreateFlagWatchRoot)
      }

      static var ignoreSelf: CreateFlags {
        return CreateFlags(rawValue: kFSEventStreamCreateFlagIgnoreSelf)
      }

      static var fileEvents: CreateFlags {
        return CreateFlags(rawValue: kFSEventStreamCreateFlagFileEvents)
      }

      static var markSelf: CreateFlags {
        return CreateFlags(rawValue: kFSEventStreamCreateFlagMarkSelf)
      }

      var hashValue: Int {
        return rawValue.hashValue
      }
    }

    struct Error: Swift.Error {
      var code: ErrorCode
      var message: String?

      init(code: ErrorCode) {
        self.code = code
      }

      init(code: ErrorCode, message: String) {
        self.code = code
        self.message = message
      }
    }

    enum ErrorCode {
      case cannotCreateStream
      case cannotStartStream
    }

    struct Event {
      var path: String
      var flags: EventFlags?
      var id: EventID?
    }

    struct EventFlags: OptionSet, Hashable {
      let rawValue: FSEventStreamEventFlags

      init(rawValue: FSEventStreamEventFlags) {
        self.rawValue = rawValue
      }

      init(rawValue: Int) {
        self.rawValue = FSEventStreamEventFlags(truncatingIfNeeded: rawValue)
      }

      static let none = EventFlags(rawValue: kFSEventStreamEventFlagNone)
      static let mustScanSubDirs = EventFlags(
        rawValue: kFSEventStreamEventFlagMustScanSubDirs
      )
      static let userDropped = EventFlags(rawValue: kFSEventStreamEventFlagUserDropped)
      static let kernelDropped = EventFlags(rawValue: kFSEventStreamEventFlagKernelDropped)
      static let idsWrapped = EventFlags(rawValue: kFSEventStreamEventFlagEventIdsWrapped)
      static let historyDone = EventFlags(rawValue: kFSEventStreamEventFlagHistoryDone)
      static let rootChanged = EventFlags(rawValue: kFSEventStreamEventFlagRootChanged)
      static let mount = EventFlags(rawValue: kFSEventStreamEventFlagMount)
      static let unmount = EventFlags(rawValue: kFSEventStreamEventFlagUnmount)
      static let itemCloned = EventFlags(rawValue: kFSEventStreamEventFlagItemCloned)
      static let itemCreated = EventFlags(rawValue: kFSEventStreamEventFlagItemCreated)
      static let itemRemoved = EventFlags(rawValue: kFSEventStreamEventFlagItemRemoved)
      static let itemInodeMetaMod = EventFlags(
        rawValue: kFSEventStreamEventFlagItemInodeMetaMod
      )
      static let itemRenamed = EventFlags(rawValue: kFSEventStreamEventFlagItemRenamed)
      static let itemModified = EventFlags(rawValue: kFSEventStreamEventFlagItemModified)
      static let itemFinderInfoMod = EventFlags(
        rawValue: kFSEventStreamEventFlagItemFinderInfoMod
      )
      static let itemChangeOwner = EventFlags(
        rawValue: kFSEventStreamEventFlagItemChangeOwner
      )
      static let itemXattrMod = EventFlags(rawValue: kFSEventStreamEventFlagItemXattrMod)
      static let itemIsFile = EventFlags(rawValue: kFSEventStreamEventFlagItemIsFile)
      static let itemIsDir = EventFlags(rawValue: kFSEventStreamEventFlagItemIsDir)
      static let itemIsSymlink = EventFlags(rawValue: kFSEventStreamEventFlagItemIsSymlink)
      static let ownEvent = EventFlags(rawValue: kFSEventStreamEventFlagOwnEvent)
      static let itemIsHardlink = EventFlags(rawValue: kFSEventStreamEventFlagItemIsHardlink)
      static let itemIsLastHardlink = EventFlags(
        rawValue: kFSEventStreamEventFlagItemIsLastHardlink
      )

      var hashValue: Int {
        return rawValue.hashValue
      }
    }

    struct EventID: Hashable, RawRepresentable {
      let rawValue: FSEventStreamEventId

      init(rawValue: FSEventStreamEventId) {
        self.rawValue = rawValue
      }

      init(rawValue: UInt) {
        self.rawValue = FSEventStreamEventId(UInt32(truncatingIfNeeded: rawValue))
      }

      static var now: EventID {
        return EventID(rawValue: kFSEventStreamEventIdSinceNow)
      }
    }

    struct CriticalError: Swift.Error {
      var code: CriticalErrorCode
      var message: String?

      init(code: CriticalErrorCode, message: String? = nil) {
        self.code = code
        self.message = message
      }
    }

    enum CriticalErrorCode {
      case missingContextRawPointerValue
      case unexpectedPathValueType
      case unmatchedEventParameterCounts
    }

    /// This isn't actually sendable, but we only send it to store a persistent
    /// strong reference to it, so this is safe for now.
    fileprivate final class EventStream: @unchecked Sendable {
      // This must be a non-nil value if an instance of this class has been created successfully.
      var rawref: FSEventStreamRef!
      private let handler: (CoreServicesFileSystemWatcher.Event) -> Void
      private let errorHandler: (Swift.Error) -> Void

      init(
        pathsToWatch: [String],
        sinceWhen: CoreServicesFileSystemWatcher.EventID,
        latency: TimeInterval,
        flags: CoreServicesFileSystemWatcher.CreateFlags,
        handler: @escaping (CoreServicesFileSystemWatcher.Event) -> Void,
        errorHandler: @escaping (Swift.Error) -> Void
      ) throws {
        // `CoreServices.FSEventStreamCallback` is C callback and follows
        // C convention. Which means it cannot capture any external value.
        let callback: CoreServices.FSEventStreamCallback = {
          (
            streamRef: ConstFSEventStreamRef,
            clientCallBackInfo: UnsafeMutableRawPointer!,
            numEvents: Int,
            eventPaths: UnsafeMutableRawPointer,
            eventFlags: UnsafePointer<FSEventStreamEventFlags>,
            eventIds: UnsafePointer<FSEventStreamEventId>
          ) -> Void in
          let unmanagedPtr: Unmanaged<CoreServicesFileSystemWatcher.EventStream> =
            Unmanaged.fromOpaque(clientCallBackInfo)
          let self1 = unmanagedPtr.takeUnretainedValue()

          do {
            let eventPaths1: CFArray = Unmanaged.fromOpaque(eventPaths)
              .takeUnretainedValue()

            guard let eventPaths2 = eventPaths1 as NSArray as? [NSString] as [String]?
            else {
              throw CriticalError(
                code: .unexpectedPathValueType,
                message: "Cannot convert `\(eventPaths1)` into [String]."
              )
            }

            guard numEvents == eventPaths2.count else {
              throw CriticalError(
                code: .unmatchedEventParameterCounts,
                message:
                  "Event count is `\(numEvents)`, but path count is `\(eventPaths2.count)`"
              )
            }

            for index in 0..<numEvents {
              let eventPath = eventPaths2[index]
              let eventFlag = eventFlags[index]
              let eventFlag1 = CoreServicesFileSystemWatcher.EventFlags(
                rawValue: eventFlag
              )
              let eventId = eventIds[index]
              let eventId1 = CoreServicesFileSystemWatcher.EventID(rawValue: eventId)
              let event = CoreServicesFileSystemWatcher.Event(
                path: eventPath,
                flags: eventFlag1,
                id: eventId1
              )
              self1.handler(event)
            }
          } catch {
            self1.errorHandler(error)
          }
        }

        self.handler = handler
        self.errorHandler = errorHandler
        let unmanagedPtr = Unmanaged.passUnretained(self)

        var context = FSEventStreamContext(
          version: 0,
          info: unmanagedPtr.toOpaque(),
          retain: nil,
          release: nil,
          copyDescription: nil
        )

        guard
          let newRawref = FSEventStreamCreate(
            nil,
            callback,
            &context,
            pathsToWatch as CFArray,
            sinceWhen.rawValue,
            latency as CFTimeInterval,
            flags.union(.useCFTypes).rawValue
          )
        else {
          throw CoreServicesFileSystemWatcher.Error(code: .cannotCreateStream)
        }
        rawref = newRawref
      }

      deinit {
        // `rawref` is a CFType, so will be deallocated automatically.
      }

      func getLatestEventID() -> CoreServicesFileSystemWatcher.EventID {
        let eventId = FSEventStreamGetLatestEventId(rawref)
        let eventID1 = CoreServicesFileSystemWatcher.EventID(rawValue: eventId)
        return eventID1
      }

      func scheduleWithRunloop(runLoop: RunLoop, runLoopMode: RunLoop.Mode) {
        let runLoopMode1 = runLoopMode as CFString
        FSEventStreamScheduleWithRunLoop(rawref, runLoop.getCFRunLoop(), runLoopMode1)
      }

      func unscheduleFromRunLoop(runLoop: RunLoop, runLoopMode: RunLoop.Mode) {
        let runLoopMode1 = runLoopMode as CFString
        FSEventStreamUnscheduleFromRunLoop(rawref, runLoop.getCFRunLoop(), runLoopMode1)
      }

      func setDispatchQueue(_ queue: DispatchQueue?) {
        FSEventStreamSetDispatchQueue(rawref, queue)
      }

      func invalidate() {
        FSEventStreamInvalidate(rawref)
      }

      func start() throws {
        switch FSEventStreamStart(rawref) {
          case false:
            throw CoreServicesFileSystemWatcher.Error.init(code: .cannotStartStream)
          case true:
            return
        }
      }

      func flushAsync() -> CoreServicesFileSystemWatcher.EventID {
        let eventId = FSEventStreamFlushAsync(rawref)
        let eventId1 = CoreServicesFileSystemWatcher.EventID(rawValue: eventId)
        return eventId1
      }

      func flushSync() {
        FSEventStreamFlushSync(rawref)
      }

      func stop() {
        FSEventStreamStop(rawref)
      }

      private func show() {
        FSEventStreamShow(rawref)
      }

      func copyDescription() -> String {
        let desc = FSEventStreamCopyDescription(rawref)
        let desc1 = desc as String
        return desc1
      }

      @discardableResult
      func setExclusionPaths(_ pathsToExclude: [String]) -> Bool {
        let pathsToExclude1 = pathsToExclude as [NSString] as NSArray as CFArray
        return FSEventStreamSetExclusionPaths(rawref, pathsToExclude1)
      }
    }
  }
#endif
