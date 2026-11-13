#if os(macOS)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Musl)
  import Musl
#elseif os(Windows)
  import WinSDK
#else
  #error("Must implement signal handling for new platforms")
#endif

#if os(macOS) || os(Linux)
  /// A signal action, typealiased to avoid confusion with the `sigaction` function.
  typealias SignalAction = sigaction

  /// A signal that can be caught.
  public enum Signal: Int32, CaseIterable {
    case hangUp
    case interrupt
    case quit
    case abort
    case kill
    case alarm
    case terminate

    public var rawValue: Int32 {
      switch self {
        case .hangUp: return SIGHUP
        case .interrupt: return SIGINT
        case .quit: return SIGQUIT
        case .abort: return SIGABRT
        case .kill: return SIGKILL
        case .alarm: return SIGALRM
        case .terminate: return SIGTERM
      }
    }
  }
#elseif os(Windows)
  public enum Signal: Int32, CaseIterable {
    case abort
    case interrupt
    case terminate

    public var rawValue: Int32 {
      switch self {
        case .abort: return SIGABRT
        case .interrupt: return SIGINT
        case .terminate: return SIGTERM
      }
    }
  }
#endif

/// Sets a trap for the specified signal.
func trap(_ signal: Signal, action: @escaping @convention(c) () -> Void) {
  #if os(macOS)
    // Modified from: https://gist.github.com/sharplet/d640eea5b6c99605ac79
    var signalAction = SignalAction(
      __sigaction_u: unsafeBitCast(action, to: __sigaction_u.self),
      sa_mask: 0,
      sa_flags: 0
    )
    sigaction(signal.rawValue, &signalAction, nil)
  #elseif canImport(Musl)
    var signalAction = SignalAction()
    signalAction.__sa_handler = unsafeBitCast(
      action,
      to: sigaction.__Unnamed_union___sa_handler.self
    )
    var mask = __sigset_t()
    sigemptyset(&mask)
    signalAction.sa_mask = mask
    signalAction.sa_flags = 0
    sigaction(signal.rawValue, &signalAction, nil)
  #elseif os(Linux)
    var signalAction = SignalAction()
    signalAction.__sigaction_handler = unsafeBitCast(
      action,
      to: sigaction.__Unnamed_union___sigaction_handler.self
    )
    var mask = __sigset_t()
    sigemptyset(&mask)
    signalAction.sa_mask = mask
    signalAction.sa_flags = 0
    sigaction(signal.rawValue, &signalAction, nil)
  #elseif os(Windows)
    WinSDK.signal(signal.rawValue, unsafeBitCast(action, to: (@convention(c) (Int32) -> Void).self))
  #endif
}
