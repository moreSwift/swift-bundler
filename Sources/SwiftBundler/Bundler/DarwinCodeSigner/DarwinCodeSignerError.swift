import Foundation
import ErrorKit

extension DarwinCodeSigner {
  typealias Error = RichError<ErrorMessage>

  /// An error message related to ``DarwinCodeSigner``.
  enum ErrorMessage: Throwable {
    case failedToEnumerateIdentities
    case failedToParseIdentityList
    case failedToRunCodesignTool
    case failedToWriteEntitlements
    case failedToLoadProvisioningProfile(URL)
    case provisioningProfileMissingTeamIdentifier
    case failedToEnumerateDynamicLibraries
    case failedToLocateSigningCertificate(CodeSigningIdentity)
    case failedToParseSigningCertificate(pem: String)
    case signingCertificateMissingTeamIdentifier(CodeSigningIdentity)
    case identityShortNameNotMatched(String)
    case invalidId(String)
    case certificateExpired(CodeSigningIdentity, notValidAfter: Date)

    var userFriendlyMessage: String {
      switch self {
        case .failedToEnumerateIdentities:
          return "Failed to enumerate code signing identities"
        case .failedToParseIdentityList:
          return "Failed to parse identity list"
        case .failedToRunCodesignTool:
          return "Failed to run 'codesign' command"
        case .failedToWriteEntitlements:
          return "Failed to write entitlements"
        case .failedToLoadProvisioningProfile(let file):
          return "Failed to load '\(file.path)'"
        case .provisioningProfileMissingTeamIdentifier:
          return "The supplied provisioning profile is missing the 'TeamIdentifier' entry"
        case .failedToEnumerateDynamicLibraries:
          return "Failed to enumerate dynamic libraries"
        case .failedToLocateSigningCertificate(let identity):
          return "Failed to locate signing certificate for identity \(identity)"
        case .failedToParseSigningCertificate(let identity):
          return "Failed to parse signing certificate for identity \(identity)"
        case .signingCertificateMissingTeamIdentifier(let identity):
          return """
            Failed to locate team identifier in signing certificate for \
            identity \(identity)
            """
        case .identityShortNameNotMatched(let shortName):
          return """
            Identity short name '\(shortName)' didn't match any known identities. \
            Run 'swift bundler list-identities' to list available identities.
            """
        case .invalidId(let id):
          return "Invalid code signing id '\(id)', expected hexadecimal string."
        case .certificateExpired(let identity, let notValidAfter):
          return """
            The certificate corresponding to code signing identity '\(identity.name)'
            with SHA-1 hash '\(identity.id)' expired at \(notValidAfter).
            """
      }
    }
  }
}
