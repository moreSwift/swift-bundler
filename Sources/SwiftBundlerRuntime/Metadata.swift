import Foundation
import SwiftBundlerRuntimeC

/// Metadata embedded in apps by Swift Bundler. Use ``Metadata/loadEmbedded()``
/// to load the metadata embedded in the current executable if any is present.
public struct Metadata {
  public var appIdentifier: String
  public var appVersion: String
  public var urlSchemes: [URLScheme]?
  public var additionalMetadata: [String: Any]

  public struct URLScheme: Codable {
    var scheme: String
  }

  /// Loads the app's embedded metadata if present and returns `nil` otherwise.
  /// - Throws: An error if metadata is present but malformed.
  public static func loadEmbedded() throws -> Metadata? {
    #if SWIFT_BUNDLER_METADATA
      guard
        let pointer: UnsafeRawPointer = SwiftBundlerRuntimeC._getSwiftBundlerMetadata(),
        let datas = UnsafePointer<Array<Array<UInt8>>>(OpaquePointer(pointer))?.pointee
      else {
        throw RuntimeError(
          message: "Failed to load metadata: inserted metadata function returned nil pointer"
        )
      }

      guard datas.count >= 1 else {
        throw RuntimeError(
          message: "Failed to parse metadata: empty data array"
        )
      }

      // Aside: If you want to decode the metadata in your own implementation without
      // foundation then you can use `String(decoding: bytes, as: UTF8.self)` if you
      // need to convert the bytes to a String.
      let bytes = datas[0]
      let json = Data(bytes)
      let jsonValue: Any
      do {
        jsonValue = try JSONSerialization.jsonObject(with: json)
      } catch {
        throw RuntimeError(
          message: "Failed to parse metadata: invalid json"
        )
      }

      guard let json = jsonValue as? [String: Any] else {
        throw RuntimeError(
          message: "Failed to parse metadata: not a json dictionary: '\(jsonValue)'"
        )
      }
      guard let identifier = json["appIdentifier"] as? String else {
        throw RuntimeError(
          message: "Failed to parse metadata: missing app identifier"
        )
      }
      guard let version = json["appVersion"] as? String else {
        throw RuntimeError(
          message: "Failed to parse metadata: missing app version"
        )
      }

      let urlSchemes: [URLScheme]?
      if let schemes = json["urlSchemes"] as? [Any] {
        urlSchemes = try schemes.map { scheme in
          guard
            let scheme = scheme as? [String: Any],
            let name = scheme["scheme"] as? String
          else {
            throw RuntimeError(
              message: "Failed to parse metadata: invalid url schemes"
            )
          }
          return URLScheme(scheme: name)
        }
      } else {
        urlSchemes = nil
      }
      
      let additionalMetadata = json["additionalMetadata"].map { value in
        value as? [String: Any] ?? [:]
      } ?? [:]

      return Metadata(
        appIdentifier: identifier,
        appVersion: version,
        urlSchemes: urlSchemes,
        additionalMetadata: additionalMetadata
      )
    #else
      return nil
    #endif
  }
}
