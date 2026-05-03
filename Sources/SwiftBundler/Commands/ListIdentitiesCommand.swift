import ArgumentParser
import Foundation

/// The command for listing codesigning identities.
struct ListIdentitiesCommand: ErrorHandledCommand {
  static var configuration = CommandConfiguration(
    commandName: "list-identities",
    abstract: "List available codesigning identities."
  )

  @Flag(
    name: .shortAndLong,
    help: "Print verbose error messages."
  )
  public var verbose = false

  func wrappedRun() async throws(RichError<SwiftBundlerError>) {
    let identities: [CodeSigningIdentity]
    if HostPlatform.hostPlatform == .macOS {
      identities = try await RichError<SwiftBundlerError>.catch {
        try await DarwinCodeSigner.enumerateIdentities()
      }
    } else if HostPlatform.hostPlatform == .windows {
      identities = try RichError<SwiftBundlerError>.catch {
        try WindowsCodeSigner.enumerateIdentities()
      }
    } else {
      throw RichError(.codesigningNotSupported(HostPlatform.hostPlatform))
    }

    Output {
      Section("Available identities") {
        KeyedList {
          for identity in identities {
            KeyedList.Entry(identity.id, "'\(identity.name)'")
          }
        }
      }
    }.show()
  }
}
