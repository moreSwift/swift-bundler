import Foundation

#if os(Windows)
  import WinSDK
#endif

/// A utility for codesigning Windows executables/libraries/installers. Only works
/// on Windows.
enum WindowsCodeSigner {
  /// The OID for codesigning certificate usage specified in the EKU field.
  static let ekuCodeSigningOID = "1.3.6.1.5.5.7.3.3"

  /// Enumerates available signing identities in the 'CurrentUser\My' certificate store.
  ///
  /// To verify its output, you can run `certutil -v -user -store My` to list all certificates
  /// in the 'CurrentUser\My' certificate store, and then ignore any that don't have a
  /// private key, and any that have the EKU field but don't have the codesigning EKU usage
  /// identifier.
  static func enumerateIdentities() async throws(Error) -> [DarwinCodeSigner.Identity] {
    #if os(Windows)
      // Inspired by https://stackoverflow.com/a/34779140/8268001
      guard let store = CertOpenSystemStoreA(0, "MY") else {
        throw Error(.failedToLoadCertificateStore("MY"))
      }
      defer { CertCloseStore(store, UInt32(CERT_CLOSE_STORE_FORCE_FLAG)) }

      var nextCertificate = CertEnumCertificatesInStore(store, nil)
      var identities: [DarwinCodeSigner.Identity] = []
      while let certificatePointer = nextCertificate {
        print("Wrap cert")
        let certificate = WinCryptCert(cert: certificatePointer)
        defer { nextCertificate = CertEnumCertificatesInStore(store, certificatePointer) }

        print("Has private key")
        guard certificate.hasPrivateKey else {
          // Certificates without code signing are useless to us
          continue
        }

        print("OIDs")
        if let ekuOIDs = certificate.ekuOIDs {
          // If the EKU information is present, we have to check whether the cert
          // is valid for codesigning.
          guard ekuOIDs.contains(ekuCodeSigningOID) else {
            continue
          }
        }

        print("Get hash")
        let hash = certificate.hash
        print("Get name")
        identities.append(
          DarwinCodeSigner.Identity(
            id: hash.map { byte in
              String(format: "%02X", byte)
            }.joined(separator: ""),
            certificateSHA1: hash,
            name: certificate.name
          )
        )
      }
      return identities
    #else
      return []
    #endif
  }

  #if os(Windows)
    /// A more Swifty wrapper around a wincrypt certificate structure.
    struct WinCryptCert {
      let cert: UnsafePointer<CERT_CONTEXT>

      var hasPrivateKey: Bool {
        let foundPrivateKey = CryptFindCertificateKeyProvInfo(cert, 0, nil)
        return foundPrivateKey
      }

      var name: String {
        let displayNameKey = UInt32(CERT_NAME_SIMPLE_DISPLAY_TYPE)
        let capacity = CertGetNameStringA(cert, displayNameKey, 0, nil, nil, 0)
        let nameBuffer = UnsafeMutableBufferPointer<CChar>.allocate(capacity: Int(capacity))
        defer { nameBuffer.deallocate() }
        CertGetNameStringA(cert, displayNameKey, 0, nil, nameBuffer.baseAddress, capacity)
        return String(cString: UnsafePointer(nameBuffer.baseAddress!))
      }

      var hash: [UInt8] {
        var hashSize: UInt32 = 0
        if !CertGetCertificateContextProperty(cert, UInt32(CERT_HASH_PROP_ID), nil, &hashSize) {
          log.debug("Failed to get hash of certificate '\(name)', skipping")
          return []
        }

        return Array<UInt8>(unsafeUninitializedCapacity: Int(hashSize)) {
            (buffer, initializedCount) in
          let succeeded = CertGetCertificateContextProperty(
            cert,
            UInt32(CERT_HASH_PROP_ID),
            buffer.baseAddress,
            &hashSize
          )
          precondition(
            succeeded,
            "Should be unreachable; size used was returned by wincrypt itself"
          )
          initializedCount = Int(hashSize)
        }
      }

      var ekuOIDs: [String]? {
        var size = UInt32(0)
        _ = CertGetEnhancedKeyUsage(cert, 0, nil, &size)
        guard size > 0 else {
          return nil
        }

        let usageData = UnsafeMutableBufferPointer<CChar>.allocate(capacity: Int(size))
        defer { usageData.deallocate() }

        return usageData.baseAddress!.withMemoryRebound(
          to: CERT_ENHKEY_USAGE.self,
          capacity: 1
        ) { pointer in
          if !CertGetEnhancedKeyUsage(cert, 0, pointer, &size) {
            log.warning("CertGetEnhancedKeyUsage failed with well-sized buffer")
            return []
          }

          var oids: [String] = []
          for index in 0..<Int(pointer.pointee.cUsageIdentifier) {
            let identifierCString = pointer.pointee.rgpszUsageIdentifier
              .advanced(by: index).pointee!
            let identifier = String(cString: identifierCString)
            oids.append(identifier)
          }
          return oids
        }
      }
    }
  #endif
}
