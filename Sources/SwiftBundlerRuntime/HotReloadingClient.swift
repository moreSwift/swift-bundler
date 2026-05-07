import FlyingSocks
import Foundation
import HotReloadingProtocol

public enum HotReloadingClientError: LocalizedError {
  case missingAddress
  case invalidAddress(details: String)

  public var errorDescription: String? {
    switch self {
      case .missingAddress:
        return "Missing SWIFT_BUNDLER_SERVER environment variable"
      case let .invalidAddress(details):
        return "Invalid IPv4 address string: \(details)"
    }
  }
}

public struct HotReloadingClient: Sendable {
  var server: AsyncSocket

  /// Connects to the server specified by the `SWIFT_BUNDLER_SERVER` environment variable.
  /// Only supports the address formats supported by ``Self/parseAddress(_:)``.
  public init() async throws {
    guard let addressString = ProcessInfo.processInfo.environment["SWIFT_BUNDLER_SERVER"] else {
      throw HotReloadingClientError.missingAddress
    }

    let (address, port) = try Self.parseAddress(addressString)
    try await self.init(address: address, port: port)
  }

  /// Connects to a hot reloading server.
  public init(address: String, port: UInt16) async throws {
    server = try await AsyncSocket.connected(to: .inet(ip4: address, port: port))
  }

  #if canImport(Darwin) || canImport(Glibc)
    public mutating func handlePackets(handleDylib: (sending Dylib) -> Void) async throws {
      while true {
        let packet = try await Packet.read(from: &server)

        switch packet {
          case .ping:
            print("Hot reloading client: Received ping")
            try await Packet.pong.write(to: &server)
          case let .reloadDylib(path):
            print("Hot reloading client: Received new dylib")
            // Copy dylib to new partially randomized path to avoid `dlopen` just giving
            // us back the same pointer again.
            let newPath =
              path
              .deletingLastPathComponent()
              .appendingPathComponent(UUID().uuidString + ".dylib")
            try FileManager.default.copyItem(
              at: path,
              to: newPath
            )
            let dylib = try Dylib.open(newPath)
            handleDylib(dylib)
            try FileManager.default.removeItem(at: newPath)
          case .pong:
            print("Hot reloading client: Received pong")
        }
      }
    }
  #endif

  /// Parses an IPv4 address of the form `x.x.x.x:yyyyy`.
  public static func parseAddress(
    _ addressString: String
  ) throws -> (address: String, port: UInt16) {
    let parts = addressString.split(separator: ":")

    guard parts.count == 2 else {
      throw HotReloadingClientError.invalidAddress(details: "Must have exactly one semicolon")
    }

    guard let port = UInt16(parts[1]) else {
      throw HotReloadingClientError.invalidAddress(details: "Port must be valid UInt16")
    }

    let bytes = parts[0]
      .split(separator: ".")
      .compactMap { byteString in
        UInt8(byteString)
      }

    guard bytes.count == 4 else {
      throw HotReloadingClientError.invalidAddress(
        details: "IP address must have exactly four valid UInt8's separated by periods"
      )
    }

    return (
      address: bytes.map(\.description).joined(separator: "."),
      port: port
    )
  }
}
