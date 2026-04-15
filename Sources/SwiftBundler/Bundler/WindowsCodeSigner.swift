import Foundation

#if os(Windows)
  import WinSDK
#endif

/// A utility for codesigning Windows executables/libraries/installers. Only works
/// on Windows.
enum WindowsCodeSigner {
  /// The OID for codesigning certificate usage specified in the EKU field.
  static let ekuCodeSigningOID = "1.3.6.1.5.5.7.3.3"

  /// The download URL for the version of Microsoft.ArtifactSigning.Client that we use.
  static let azureArtifactSigningNUPKG =
    URL(string: "https://www.nuget.org/api/v2/package/Microsoft.ArtifactSigning.Client/1.0.128")!

  /// Signs a file using the given code signing context. Also securely timestamps the file.
  static func signFile(
    _ file: URL,
    context: BundlerContext.WindowsCodeSigningContext
  ) async throws(Error) {
    switch context {
      case .azureArtifactSigning(let metadata):
        try await signFile(file, azureArtifactSigningMetadata: metadata)
      case .localCertificate(let identity):
        try await signFile(file, identity: identity)
    }
  }

  /// Signs a file using the given code signing identity. Also securely timestamps the file.
  static func signFile(_ file: URL, identity: CodeSigningIdentity) async throws(Error) {
    try await Error.catch {
      try await Process.create(
        "SignTool",
        arguments: [
          "sign",
          "/fd", "SHA256",
          "/tr", "http://timestamp.digicert.com",
          "/td", "SHA256",
          "/sha1", identity.id,
          file.path
        ]
      ).runAndWait()
    }
  }

  /// Signs a file using the given code signing identity. Also securely timestamps the file.
  static func signFile(_ file: URL, azureArtifactSigningMetadata: URL) async throws(Error) {
    let clientDLL = try await ensureArtifactSigningDLL()
    try await Error.catch {
      try await Process.create(
        "SignTool",
        arguments: [
          "sign",
          "/fd", "SHA256",
          "/tr", "http://timestamp.acs.microsoft.com",
          "/td", "SHA256",
          "/dlib", clientDLL.path,
          "/dmdf", azureArtifactSigningMetadata.path,
          file.path
        ]
      ).runAndWait()
    }
  }

  /// Ensures that the Azure Artifact Signing Client dll has been downloaded,
  /// and returns its location. Downloads the client if necessary.
  private static func ensureArtifactSigningDLL() async throws(Error) -> URL {
    let toolsDirectory = try Error.catch {
      try System.getToolsDirectory()
    }

    let artifactSigningDirectory = toolsDirectory / "Azure.CodeSigning.Client"
    let dll = artifactSigningDirectory / "bin" / "x64" / "Azure.CodeSigning.Dlib.dll"
    if dll.exists() {
      return dll
    }

    log.info("Downloading Azure Artifact Signing Dlib")
    log.debug("Downloading from \(azureArtifactSigningNUPKG.absoluteString)")
    let uuid = UUID().uuidString
    let temp = FileManager.default.temporaryDirectory
    let artifactSigningZip = temp / "AzureArtifactSigningClient-\(uuid).zip"
    try Error.catch(withMessage: .failedToDownloadArtifactSigningClient) {
      let content = try Data(contentsOf: azureArtifactSigningNUPKG)
      try content.write(to: artifactSigningZip)
      try FileManager.default.unzipItem(at: artifactSigningZip, to: artifactSigningDirectory)
    }

    defer {
      try? FileManager.default.removeItem(at: artifactSigningZip)
    }

    return dll
  }

  /// Resolve an identity search term to a specific identity. If multiple identities match
  /// then one of the matches is chosen using an approach that remains stable across runs.
  static func resolveIdentity(searchTerm: String) throws -> CodeSigningIdentity {
    let identities = try enumerateIdentities()
    let normalizedSearchTerm = searchTerm.lowercased()
    if let identity = identities.first(where: { $0.id.lowercased() == normalizedSearchTerm }) {
      return identity
    }

    let matches = identities.filter { identity in
      identity.name.lowercased().contains(normalizedSearchTerm)
      || identity.id.lowercased().contains(normalizedSearchTerm)
    }

    guard let match = matches.first else {
      throw Error(.identityNotFound(searchTerm))
    }

    if matches.count > 1 {
      log.warning("Multiple identities match '\(searchTerm)', using \(match)")
      log.debug("Matches: \(matches)")
    }

    return match
  }

  /// Enumerates available signing identities in the 'CurrentUser\My' certificate store.
  ///
  /// To verify its output, you can run `certutil -v -user -store My` to list all certificates
  /// in the 'CurrentUser\My' certificate store, and then ignore any that don't have a
  /// private key, and any that have the EKU field but don't have the codesigning EKU usage
  /// identifier.
  static func enumerateIdentities() throws(Error) -> [CodeSigningIdentity] {
    #if os(Windows)
      // Inspired by https://stackoverflow.com/a/34779140/8268001
      guard let store = CertOpenSystemStoreA(0, "MY") else {
        throw Error(.failedToLoadCertificateStore("MY"))
      }
      defer { CertCloseStore(store, UInt32(CERT_CLOSE_STORE_FORCE_FLAG)) }

      var nextCertificate = CertEnumCertificatesInStore(store, nil)
      var identities: [CodeSigningIdentity] = []
      while let certificatePointer = nextCertificate {
        let certificate = WinCryptCert(cert: certificatePointer)
        defer { nextCertificate = CertEnumCertificatesInStore(store, certificatePointer) }

        guard certificate.hasPrivateKey else {
          // Certificates without code signing are useless to us
          continue
        }

        if let ekuOIDs = certificate.ekuOIDs {
          // If the EKU information is present, we have to check whether the cert
          // is valid for codesigning.
          guard ekuOIDs.contains(ekuCodeSigningOID) else {
            continue
          }
        }

        let hash = certificate.hash
        identities.append(
          CodeSigningIdentity(
            id: hash.map { byte in
              String(format: "%02X", byte)
            }.joined(separator: ""),
            certificateSHA1: hash,
            name: certificate.name
          )
        )
      }

      return identities.sorted { first, second in
        // Sort for a stable ordering in case of multiple matches
        (first.name, first.id) <= (second.name, second.id)
      }
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
