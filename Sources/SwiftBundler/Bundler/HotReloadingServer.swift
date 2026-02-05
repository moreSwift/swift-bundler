#if SUPPORT_HOT_RELOADING
  import Foundation
  import FileSystemWatcher
  import FlyingSocks
  import HotReloadingProtocol
  import ErrorKit

  #if canImport(Darwin)
    import Darwin
  #elseif canImport(Glibc)
    import Glibc
  #elseif canImport(WinSDK)
    import WinSDK.WinSock2
  #endif

  struct HotReloadingServer {
    let port: UInt16
    let socket: AsyncSocket

    typealias Error = RichError<ErrorMessage>

    enum ErrorMessage: Throwable {
      case failedToSendPing
      case expectedPong(Packet)
      case addrInUse
      case failedToCreateSocket
      case failedToAcceptConnection
      case failedToWatchPackage

      var userFriendlyMessage: String {
        switch self {
          case .failedToSendPing:
            return "Failed to send ping"
          case .expectedPong(let response):
            return "Expected pong, got '\(response)'"
          case .addrInUse:
            return "Failed to create socket: Address in use"
          case .failedToCreateSocket:
            return "Failed to create socket"
          case .failedToAcceptConnection:
            return "Failed to accept connection"
          case .failedToWatchPackage:
            return "Failed to watch package for source changes"
        }
      }
    }

    static func create(portHint: UInt16 = 7331) async throws(Error) -> Self {
      var port = portHint

      // Attempt to create socket and if the address is already in use, retry with
      // higher and higher ports until socket creation fails for another reason or
      // a free address is found.
      while true {
        do {
          let socket = try await Self.createSocket(port: port)
          return Self(port: port, socket: socket)
        } catch {
          guard case .addrInUse = error.message else {
            throw error
          }

          port += 1
        }
      }
    }

    static func createSocket(port: UInt16) async throws(Error) -> AsyncSocket {
      do {
        // FlyingSocks relies on type inference tricks to hide away sockaddr_in,
        // but using them here breaks our Linux CI, so just spell it out and hope
        // FlyingSocks doesn't break this if/when they introduce more Swifty
        // SocketAddress wrappers (which would be very welcome regardless).
        let address = try sockaddr_in.inet(ip4: "127.0.0.1", port: port)
        let socket = try Socket(domain: Int32(type(of: address).family))
        try socket.bind(to: address)
        try socket.listen()

        let pool = SocketPool.make()
        try await pool.prepare()
        Task {
          try await pool.run()
        }

        return try AsyncSocket(
          socket: socket,
          pool: pool
        )
      } catch let error as SocketError {
        let addrInUse: Int32
        #if canImport(Darwin) || canImport(Glibc)
          addrInUse = EADDRINUSE
        #elseif canImport(WinSDK)
          addrInUse = WSAEADDRINUSE
        #endif

        guard
          case let .failed(_, errno, _) = error,
          errno == addrInUse
        else {
          throw Error(.failedToCreateSocket)
        }

        throw Error(.addrInUse)
      } catch {
        throw Error(.failedToCreateSocket)
      }
    }

    func start(
      product: String,
      buildContext: GenericBuildContext,
      swiftToolchain: URL?,
      appConfiguration: AppConfiguration.Flat
    ) async throws(Error) {
      let connection = try await accept()
      log.debug("Received connection from runtime")

      try await Self.handshake(connection)
      log.debug("Handshake succeeded")

      let sourcesDirectory = buildContext.projectDirectory / "Sources"
      let outputDirectory = BundleCommand.outputDirectory(
        for: buildContext.scratchDirectory
      )
      let metadataDirectory = outputDirectory / "metadata"

      try await Error.catch(withMessage: .failedToWatchPackage) {
        try await FileSystemWatcher.watch(
          paths: [sourcesDirectory.path],
          with: {
            log.info("Building 'lib\(product).dylib'")
            Task {
              do {
                var connection = connection

                let compiledMetadata = try await RichError<SwiftBundlerError>.catch {
                  return try await MetadataInserter.compileMetadata(
                    in: metadataDirectory,
                    for: MetadataInserter.metadata(for: appConfiguration),
                    architectures: buildContext.architectures,
                    platform: buildContext.platform
                  )
                }

                let context = SwiftPackageManager.BuildContext(
                  genericContext: buildContext,
                  toolchain: swiftToolchain,
                  hotReloadingEnabled: true,
                  isGUIExecutable: true,
                  compiledMetadata: compiledMetadata
                )

                let dylibFile = try await SwiftPackageManager.buildExecutableAsDylib(
                  product: product,
                  buildContext: context
                )
                log.info("Successfully built dylib")

                try await Packet.reloadDylib(path: dylibFile).write(to: &connection)
              } catch {
                log.error("Hot reloading failed: \(error.localizedDescription)")
              }
            }
          },
          errorHandler: { error in
            log.error("Hot reloading failed: \(error.localizedDescription)")
          }
        )
      }
    }

    func accept() async throws(Error) -> AsyncSocket {
      try await Error.catch(withMessage: .failedToAcceptConnection) {
        try await socket.accept()
      }
    }

    static func handshake(_ connection: AsyncSocket) async throws(Error) {
      var connection = connection
      let response = try await Error.catch(withMessage: .failedToSendPing) {
        try await Packet.ping.write(to: &connection)
        return try await Packet.read(from: &connection)
      }

      guard case Packet.pong = response else {
        throw Error(.expectedPong(response))
      }
    }
  }
#endif
