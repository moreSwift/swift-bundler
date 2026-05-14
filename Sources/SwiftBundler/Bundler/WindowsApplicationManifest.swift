import Foundation
import XMLCoder

/// A Windows application manifest. Fields not marked as required in their
/// documentation optional. We have not modelled required fields as
/// non-optional types, because we want to be able to reuse this type as a
/// manifest overlay type as well, allowing users to specify partial manifests
/// that then get merged with our generated manifests.
///
/// See https://learn.microsoft.com/en-us/windows/win32/sbscs/application-manifests.
struct WindowsApplicationManifest:
  Codable, DynamicNodeEncoding, TriviallyFlattenable, Hashable, Sendable
{
  /// This is a required field.
  var manifestVersion: String?
  /// This is a required field.
  var assemblyIdentity: AssemblyIdentity?
  var description: String?
  var trustInfo: TrustInfo?
  var file: File?

  static func nodeEncoding(for key: any CodingKey) -> XMLEncoder.NodeEncoding {
    switch key as? CodingKeys {
      case .manifestVersion: .attribute
      case .assemblyIdentity, .description, .trustInfo, _: .element
    }
  }

  /// Encodes the manifest as XML.
  func encode() throws -> Data {
    let encoder = XMLEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    encoder.prettyPrintIndentation = .spaces(4)
    return try encoder.encode(
      self,
      withRootKey: "assembly",
      rootAttributes: [
        "xmlns": "urn:schemas-microsoft-com:asm.v1"
      ],
      header: XMLHeader(version: 1.0, encoding: "UTF-8", standalone: "yes")
    )
  }

  struct AssemblyIdentity: Codable, DynamicNodeEncoding, Hashable, Sendable {
    /// This is a required field.
    var version: String?
    var processorArchitecture: String?
    /// This is a required field.
    var name: String?
    /// This is a required field, and only has one possible value.
    var type: AssemblyType?

    static func nodeEncoding(for key: any CodingKey) -> XMLEncoder.NodeEncoding {
      .attribute
    }

    enum AssemblyType: String, Codable, Hashable, Sendable {
      case win32
    }

    enum Architecture: String, Codable, Hashable, Sendable {
      case x86
      case amd64
      case arm
      case arm64
      case any = "*"
    }
  }

  struct TrustInfo: Codable, DynamicNodeEncoding, Hashable, Sendable {
    static let xmlns = "urn:schemas-microsoft-com:asm.v2"

    /// This is a required field.
    var xmlns: String?
    var security: Security?

    init(xmlns: String?, security: Security?) {
      self.xmlns = xmlns ?? Self.xmlns
      self.security = security
    }

    static func nodeEncoding(for key: any CodingKey) -> XMLEncoder.NodeEncoding {
      switch key as? CodingKeys {
        case .xmlns: .attribute
        case .security, _: .element
      }
    }

    struct Security: Codable, DynamicNodeEncoding, Hashable, Sendable {
      var requestedPrivileges: [PrivilegeRequest]?

      static func nodeEncoding(for key: any CodingKey) -> XMLEncoder.NodeEncoding {
        .element
      }
    }

    enum PrivilegeRequest: Codable, Hashable, Sendable {
      case requestedExecutionLevel(level: Attribute<String?>, uiAccess: Attribute<Bool?>)

      enum CodingKeys: String, CodingKey, XMLChoiceCodingKey {
        case requestedExecutionLevel
      }
    }

    struct RequestedExecutionLevel: Codable, DynamicNodeEncoding, Hashable, Sendable {
      var level: String?
      var uiAccess: Bool?

      static func nodeEncoding(for key: any CodingKey) -> XMLEncoder.NodeEncoding {
        .attribute
      }
    }
  }

  struct File: Codable, DynamicNodeEncoding, Hashable, Sendable {
    var name: String?

    static func nodeEncoding(for key: any CodingKey) -> XMLEncoder.NodeEncoding {
      .attribute
    }
  }
}
