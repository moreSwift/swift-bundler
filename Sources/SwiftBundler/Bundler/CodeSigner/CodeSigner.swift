import Foundation
import Parsing
import Crypto
import SwiftASN1
import X509

/// A utility for codesigning Darwin application bundles
enum CodeSigner {
  /// The path to the `codesign` tool.
  static let codesignToolPath = "/usr/bin/codesign"
  /// The path to the `security` tool.
  static let securityToolPath = "/usr/bin/security"
  /// We warn the user when they attempt to use a certificate within a certain
  /// margin of its expiry.
  static let certificateExpiryWarningMargin: TimeInterval = 24 * 60 * 60

  /// An identity that can be used to codesign a bundle.
  struct Identity: CustomStringConvertible {
    /// The identity's id, which is the SHA-1 hash of the corresponding
    /// certificate's DER representation.
    var id: String
    /// This is the parsed representation of ``id``, and is the SHA-1 hash of
    /// the corresponding certificate's DER representation.
    var certificateSHA1: [UInt8]
    /// The identity's display name.
    var name: String

    var description: String {
      "'\(name)' (\(id))"
    }
  }

  /// Generates an iOS entitlements file.
  /// - Parameters:
  ///   - outputFile: The destination for the generated entitlements file.
  ///   - bundle: The app bundle to sign.
  ///   - identityId: The id of the codesigning identity to use.
  ///   - bundleIdentifier: The identifier of the app bundle.
  /// - Returns: A failure if the `codesign` command fails to run.
  static func generateEntitlementsFile(
    at outputFile: URL,
    for bundle: URL,
    identityId: String,
    bundleIdentifier: String
  ) async throws(Error) {
    let teamIdentifier = try await extractTeamIdentifier(from: bundle)

    let entitlementsContent = generateEntitlementsContent(
      teamIdentifier: teamIdentifier,
      bundleIdentifier: bundleIdentifier
    )

    try Error.catch(withMessage: .failedToWriteEntitlements) {
      try entitlementsContent.write(to: outputFile)
    }
  }

  /// Signs a Darwin app bundle.
  ///
  /// If no entitlements are provided and the platform requires provisioning
  /// profiles, some basic entitlements get automatically generated. Otherwise
  /// the application bundle will fail to verify.
  /// - Parameters:
  ///   - bundle: The app bundle to sign.
  ///   - identityId: The id of the codesigning identity to use.
  ///   - bundleIdentifier: The app's bundle identifier.
  ///   - platform: The target platform getting built for.
  ///   - entitlements: The app's entitlements file.
  /// - Returns: A failure if the `codesign` command fails to run.
  static func signAppBundle(
    bundle: URL,
    identityId: String,
    bundleIdentifier: String,
    platform: ApplePlatform,
    entitlements: URL?
  ) async throws(Error) {
    log.info("Codesigning app bundle")

    let librariesDirectory = bundle.appendingPathComponent("Libraries")
    if librariesDirectory.exists(withType: .directory) {
      let contents = try Error.catch(withMessage: .failedToEnumerateDynamicLibraries) {
        try FileManager.default.contentsOfDirectory(
          at: librariesDirectory,
          includingPropertiesForKeys: nil
        )
      }

      for file in contents where file.pathExtension == "dylib" {
        try await sign(file: file, identityId: identityId)
      }
    }

    // Generate entitlements file if required by platform and not provided
    let entitlementsFile: URL?
    if let entitlements = entitlements {
      entitlementsFile = entitlements
    } else if platform.requiresProvisioningProfiles {
      let file =
        FileManager.default.temporaryDirectory
        / "\(UUID().uuidString).xcent"

      entitlementsFile = file

      try await CodeSigner.generateEntitlementsFile(
        at: file,
        for: bundle,
        identityId: identityId,
        bundleIdentifier: bundleIdentifier
      )
    } else {
      entitlementsFile = nil
    }

    try await sign(
      file: bundle,
      identityId: identityId,
      entitlements: entitlementsFile
    )
  }

  /// Signs a binary or app bundle.
  /// - Parameters:
  ///   - bundle: The binary or app bundle to sign.
  ///   - identityId: The id of the codesigning identity to use.
  ///   - entitlements: The entitlements to give the file (only valid for app bundles).
  /// - Returns: A failure if the `codesign` command fails.
  static func sign(
    file: URL,
    identityId: String,
    entitlements: URL? = nil
  ) async throws(Error) {
    let entitlementArguments: [String]
    if let entitlements = entitlements {
      entitlementArguments = [
        "--entitlements", entitlements.path,
        "--generate-entitlement-der",
      ]
    } else {
      entitlementArguments = []
    }

    let arguments =
      entitlementArguments + [
        "--force", "--deep",
        "--sign", identityId,
        file.path,
      ]

    try await Error.catch(withMessage: .failedToRunCodesignTool) {
      try await Process.create(
        codesignToolPath,
        arguments: arguments
      ).runAndWait()
    }
  }

  /// Signs a binary or app bundle using ad-hoc signing.
  /// - Parameter file: The file to sign.
  /// - Returns: A failure if the `codesign` command fails.
  static func signAdHoc(file: URL) async throws(Error) {
    try await Error.catch(withMessage: .failedToRunCodesignTool) {
      try await Process.create(
        codesignToolPath,
        arguments: ["--force", "-s", "-", file.path]
      ).runAndWait()
    }
  }

  /// Enumerates the user's available codesigning identities.
  /// - Returns: An array of identities.
  static func enumerateIdentities() async throws(Error) -> [Identity] {
    let process = Process.create(
      securityToolPath,
      arguments: ["find-identity", "-pcodesigning", "-v"]
    )

    let output: String
    do {
      output = try await process.getOutput()
    } catch {
      throw Error(.failedToEnumerateIdentities, cause: error)
    }

    // Example input: `52635337831A02427192D4FC5EC8528323456F17 "Apple Development: stackotter@stackotter.dev (LK3JHG2345)"`
    let identityParser = Parse {
      PrefixThrough(") ")
      PrefixUpTo(" ").map { (id: Substring) in
        String(id)
      }
      " "
      OneOf {
        PrefixUpTo("\n")
        Rest<Substring>()
      }.map { (substring: Substring) -> String in
        // Remove quotation marks
        let withoutQuotationMarks: Substring = substring.dropFirst().dropLast()
        return String(withoutQuotationMarks)
      }
    }.map { (_: Substring, id: String, name: String) in
      (id: id, name: name)
    }

    let identityListParser = Parse {
      Many {
        identityParser
      }
      Rest<Substring>()
    }.map { (identities: [(id: String, name: String)], _: Substring) in
      return identities
    }

    let identities: [Identity]
    do {
      identities = try identityListParser.parse(output)
        .map { (id, name) in
          guard let parsedId = Array(fromHex: id) else {
            throw Error(.invalidId(id))
          }
          return Identity(id: id, certificateSHA1: parsedId, name: name)
        }
    } catch {
      throw Error(.failedToParseIdentityList, cause: error)
    }

    return identities
  }

  /// Resolves a short-hand identity name. Can either be a full identity id or
  /// a substring of an identity's display name.
  static func resolveIdentity(
    shortName: String
  ) async throws(Error) -> Identity {
    let identities = try await enumerateIdentities()
    let matchingIdentities = identities.filter { identity in
      identity.id == shortName || identity.name.contains(shortName)
    }
    guard let identity = matchingIdentities.first else {
      throw Error(.identityShortNameNotMatched(shortName))
    }

    if matchingIdentities.count > 1 {
      log.warning(
        "Multiple identities matched short name '\(shortName)'; using '\(identity)'"
      )
      log.debug("Matching identities: \(matchingIdentities)")
    }

    return identity
  }

  static func loadCertificate(
    for identity: Identity
  ) async throws(Error) -> Certificate {
    let output: String
    do {
      output = try await Process.create(
        securityToolPath,
        arguments: [
          "find-certificate", "-c", identity.id, "-p", "-a",
        ]
      ).getOutput()
    } catch {
      throw Error(.failedToLocateSigningCertificate(identity), cause: error)
    }

    let separator = "-----BEGIN CERTIFICATE-----\n"
    let certificates = output.components(separatedBy: separator).filter { part in
      !part.isEmpty
    }.map { part in
      // Add separator back to each certificate
      String(separator + part)
    }.filter { certificatePEM in
      let base64 = certificatePEM.split(separator: "\n")
        .dropFirst().dropLast()
        .joined(separator: "")

      guard let certificateDER = Data(base64Encoded: base64) else {
        log.warning("Malformed PEM certificate")
        return false
      }
      
      let hash = Crypto.Insecure.SHA1.hash(data: certificateDER)
      return hash == identity.certificateSHA1
    }

    guard let certificatePEM = certificates.first else {
      throw Error(.failedToLocateCertificate(identity))
    }

    if certificates.count > 1 {
      log.warning(
        """
        Found multiple certificates matching identity '\(identity.name)' \
        with SHA-1 hash '\(identity.id)'.
        """
      )
    }

    let certificate: Certificate
    do {
      certificate = try Certificate(pemEncoded: certificatePEM)
    } catch {
      throw Error(
        .failedToParseSigningCertificate(pem: certificatePEM),
        cause: error
      )
    }

    guard Date() <= certificate.notValidAfter else {
      throw Error(.certificateExpired(identity, notValidAfter: certificate.notValidAfter))
    }

    if Date().advanced(by: certificateExpiryWarningMargin) >= certificate.notValidAfter {
      log.warning(
        """
        The certificate with SHA-1 hash '\(identity.id)' corresponding to \
        identity '\(identity.name)' expires soon; not valid after \
        \(certificate.notValidAfter)
        """)
    }

    return certificate
  }

  static func getTeamIdentifier(for identity: Identity) async throws(Error) -> String {
    let certificate = try await loadCertificate(for: identity)

    for element in certificate.subject {
      for attribute in element {
        guard
          attribute.type == ASN1ObjectIdentifier.RDNAttributeType.organizationalUnitName
        else {
          continue
        }
        return attribute.value.description
      }
    }

    throw Error(.signingCertificateMissingTeamIdentifier(identity))
  }

  static func extractTeamIdentifier(from bundle: URL) async throws(Error) -> String {
    let provisioningProfile = bundle / "embedded.mobileprovision"
    let profile: ProvisioningProfile
    do {
      profile = try await ProvisioningProfileManager
        .loadProvisioningProfile(provisioningProfile)
    } catch {
      throw Error(.failedToLoadProvisioningProfile(provisioningProfile), cause: error)
    }

    guard let identifier = profile.teamIdentifierArray.first else {
      throw Error(.provisioningProfileMissingTeamIdentifier)
    }

    return identifier
  }

  /// Generates the contents of an entitlements file.
  static func generateEntitlementsContent(
    teamIdentifier: String,
    bundleIdentifier: String
  ) -> String {
    return """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
      	<key>application-identifier</key>
      	<string>\(teamIdentifier).\(bundleIdentifier)</string>
      	<key>com.apple.developer.team-identifier</key>
      	<string>\(teamIdentifier)</string>
      	<key>get-task-allow</key>
      	<true/>
      </dict>
      </plist>
      """
  }
}
