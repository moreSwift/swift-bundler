import Foundation
import ErrorKit

#if SUPPORT_XCODEPROJ
  import PathKit
  import ProjectSpec
  import XcodeGenKit
  import Crypto
#endif

/// A provisioning profile manager. Can locate existing provisioning profiles,
/// and generate new ones if required.
enum ProvisioningProfileManager {
  /// The path to the `openssl` tool.
  static let opensslToolPath = "/usr/bin/openssl"

  /// Ignore profiles within 12 hours of expiry.
  static let expirationBufferSeconds: Double = 60 * 12

  /// Attempts to locate or generate a provisioning profile suitable for the
  /// given configuration.
  static func locateOrGenerateSuitableProvisioningProfile(
    bundleIdentifier: String,
    deviceId: String,
    deviceOS: NonMacAppleOS,
    identity: CodeSigningIdentity
  ) async throws(Error) -> URL {
    #if SUPPORT_XCODEPROJ
      let provisioningProfile = try await locateSuitableProvisioningProfile(
        bundleIdentifier: bundleIdentifier,
        deviceId: deviceId,
        deviceOS: deviceOS,
        identity: identity
      )

      if let provisioningProfile {
        log.debug("Found suitable provisioning profile at \(provisioningProfile.path)")
        return provisioningProfile
      }

      let teamIdentifier = try await Error.catch {
        try await DarwinCodeSigner.getTeamIdentifier(for: identity)
      }

      return try await generateProvisioningProfile(
        bundleIdentifier: bundleIdentifier,
        teamId: teamIdentifier,
        deviceId: deviceId,
        deviceOS: deviceOS
      )
    #else
      throw Error(.hostPlatformNotSupported)
    #endif
  }

  /// Returns nil if the search went smoothly but returned not matching results.
  /// Always returns an error on non-macOS hosts (not supported, yet...).
  static func locateSuitableProvisioningProfile(
    bundleIdentifier: String,
    deviceId: String,
    deviceOS: NonMacAppleOS,
    identity: CodeSigningIdentity
  ) async throws(Error) -> URL? {
    #if SUPPORT_XCODEPROJ
      let profiles = try await loadProvisioningProfiles()
      return profiles.filter { (_, profile) in
        profile.provisionedDevices?.contains(deviceId) != false
          && profile.expirationDate > Date().advanced(by: expirationBufferSeconds)
          && profile.platforms.contains(deviceOS.provisioningProfileName)
          && profile.suitable(forBundleIdentifier: bundleIdentifier)
          && profile.certificates.contains { certificate in
            Crypto.Insecure.SHA1.hash(data: Data(certificate.derEncoded))
              == identity.certificateSHA1
          }
      }.first?.0
    #else
      throw Error(.hostPlatformNotSupported)
    #endif
  }

  static func loadProvisioningProfile(
    _ provisioningProfile: URL
  ) async throws(Error) -> ProvisioningProfile {
    #if SUPPORT_XCODEPROJ
      let plistContent: String
      do {
        plistContent = try await Process.create(
          opensslToolPath,
          arguments: [
            "smime", "-verify",
            "-in", provisioningProfile.path,
            "-noverify",
            "-inform", "der",
          ]
        ).getOutput(excludeStdError: true)
      } catch {
        throw Error(
          .failedToExtractProvisioningProfilePlist(provisioningProfile),
          cause: error
        )
      }

      do {
        return try PropertyListDecoder().decode(
          ProvisioningProfile.self,
          from: Data(plistContent.utf8)
        )
      } catch {
        throw Error(
          .failedToDeserializeProvisioningProfile(provisioningProfile),
          cause: error
        )
      }
    #else
      throw Error(.hostPlatformNotSupported)
    #endif
  }

  #if SUPPORT_XCODEPROJ
    private static func loadProvisioningProfiles()
      async throws(Error) -> [(URL, ProvisioningProfile)]
    {
      let provisioningProfilesDirectory = try locateProvisioningProfilesDirectory()

      let provisioningProfiles = try FileManager.default.contentsOfDirectory(
        at: provisioningProfilesDirectory,
        errorMessage: ErrorMessage.failedToEnumerateProfiles
      )

      return try await provisioningProfiles.filter { file in
        file.pathExtension == "mobileprovision"
      }.typedAsyncMap { (profileFile: URL) async throws(Error) -> (URL, ProvisioningProfile) in
        let loadedProfile = try await loadProvisioningProfile(profileFile)
        return (profileFile, loadedProfile)
      }
    }

    private static func locateProvisioningProfilesDirectory() throws(Error) -> URL {
      do {
        let libraryDirectory = try FileManager.default.url(
          for: .libraryDirectory,
          in: .userDomainMask,
          appropriateFor: nil,
          create: false
        )

        return libraryDirectory / "Developer/Xcode/UserData/Provisioning Profiles"
      } catch {
        throw Error(.failedToLocateLibraryDirectory, cause: error)
      }
    }

    private static func generateProvisioningProfile(
      bundleIdentifier: String,
      teamId: String,
      deviceId: String,
      deviceOS: NonMacAppleOS
    ) async throws(Error) -> URL {
      log.info("Generating provisioning profile")

      let projectDirectory =
        FileManager.default.temporaryDirectory
        / "DummyProject-\(UUID().uuidString)"

      let (xcodeprojFile, scheme) = try generateDummyXcodeProject(
        projectDirectory: projectDirectory,
        bundleIdentifier: bundleIdentifier,
        teamId: teamId,
        deviceId: deviceId,
        deviceOS: deviceOS
      )

      let output: String
      do {
        output = try await Process.create(
          "xcodebuild",
          arguments: [
            "-project", xcodeprojFile.path,
            "-scheme", scheme,
            "-sdk", deviceOS.physicalPlatform.platform.sdkName,
            "-destination", "id=\(deviceId)",
            "-allowProvisioningUpdates",
            "-allowProvisioningDeviceRegistration",
            "build",
          ]
        ).getOutput(excludeStdError: false)
      } catch {
        guard
          case .nonZeroExitStatusWithOutput(let data, _, _) = error.message,
          let output = String(data: data, encoding: .utf8)
        else {
          throw Error(.failedToRunXcodebuildAutoProvisioning(message: nil), cause: error)
        }

        let message: String?
        if output.contains("Failed Registering Bundle Identifier") {
          message = """
            Bundle identifier '\(bundleIdentifier)' is already taken. Change \
            your bundle identifier to a unique string and try again
            """
        } else {
          message = nil
        }

        throw Error(.failedToRunXcodebuildAutoProvisioning(message: message), cause: error)
      }

      // We attempt to locate and parse the following part of xcodebuild's output;
      // ```
      //     Provisioning Profile: "iOS Team Provisioning Profile: *"
      //                           (c48afb72-3423-4345-bca7-c31232d09b64)
      // ```
      let lines = output.split(separator: "\n")
      guard
        let profileLineIndex = lines.firstIndex(where: { line in
          line.hasPrefix("    Provisioning Profile: ")
        }),
        profileLineIndex + 1 < lines.count
      else {
        log.debug("\(output)")
        let message = "Failed to locate generated provisioning profile ID"
        throw Error(.failedToParseXcodebuildOutput(message))
      }

      let profileId = lines[profileLineIndex + 1]
        .trimmingCharacters(in: .whitespaces)
        .dropFirst()
        .dropLast()

      let file = try locateProvisioningProfilesDirectory()
        / "\(profileId).mobileprovision"

      guard file.exists() else {
        throw Error(.failedToLocateGeneratedProvisioningProfile(file))
      }

      return file
    }

    private static func generateDummyXcodeProject(
      projectDirectory: URL,
      bundleIdentifier: String,
      teamId: String,
      deviceId: String,
      deviceOS: NonMacAppleOS
    ) throws(Error) -> (xcodeprojFile: URL, scheme: String) {
      let sourcesDirectory = projectDirectory / "Sources"
      let infoPlistFile = sourcesDirectory / "Info.plist"
      let xcodeprojFile = projectDirectory / "Dummy.xcodeproj"

      do {
        try FileManager.default.createDirectory(at: sourcesDirectory)
      } catch {
        let message = "Failed to create sources directory at '\(sourcesDirectory.path)'"
        throw Error(
          .failedToGenerateDummyXcodeproj(message: message),
          cause: error
        )
      }

      // Generate project spec
      let (project, productName) = try generateDummyXcodeProjectSpec(
        bundleIdentifier: bundleIdentifier,
        teamId: teamId,
        deviceOS: deviceOS,
        projectDirectory: projectDirectory,
        sourcesDirectory: sourcesDirectory,
        infoPlistFile: infoPlistFile
      )

      let dummySourceCode = "print(\"Hello, World!\")"
      let infoPlist: [String: Any] = [
        "CFBundleExecutable": productName,
        "CFBundleIdentifier": bundleIdentifier,
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": productName,
        "CFBundlePackageType": "APPL",
      ]

      // Create main.swift and Info.plist
      do {
        try dummySourceCode.write(to: sourcesDirectory / "main.swift")

        let data = try PropertyListSerialization.data(
          fromPropertyList: infoPlist,
          format: .xml,
          options: 0
        )

        try data.write(to: infoPlistFile)
      } catch {
        throw Error(.failedToGenerateDummyXcodeproj(message: nil), cause: error)
      }

      guard let userName = ProcessInfo.processInfo.environment["LOGNAME"] else {
        let message = "Missing username (read from LOGNAME environment variable)"
        throw Error(.failedToGenerateDummyXcodeproj(message: message))
      }

      // Generate project on disk
      let generator = ProjectGenerator(project: project)
      do {
        let xcodeProject = try generator.generateXcodeProject(
          in: Path(projectDirectory.path),
          userName: userName
        )
        let fileWriter = FileWriter(project: project)
        try fileWriter.writeXcodeProject(
          xcodeProject,
          to: Path(xcodeprojFile.path)
        )
      } catch {
        throw Error(.failedToGenerateDummyXcodeproj(message: nil), cause: error)
      }

      return (xcodeprojFile, productName)
    }

    private static func generateDummyXcodeProjectSpec(
      bundleIdentifier: String,
      teamId: String,
      deviceOS: NonMacAppleOS,
      projectDirectory: URL,
      sourcesDirectory: URL,
      infoPlistFile: URL
    ) throws(Error) -> (project: Project, productName: String) {
      let bundleIdentifierParts = bundleIdentifier.split(separator: ".")
      let bundleIdentifierPrefix = bundleIdentifierParts.dropLast()
        .joined(separator: ".")

      guard
        let productName = bundleIdentifier.split(separator: ".").last
          .map(String.init)
      else {
        throw Error(.failedToParseBundleIdentifier(bundleIdentifier))
      }

      let target = Target(
        name: productName,
        type: .application,
        platform: deviceOS.xcodePlatform,
        settings: Settings(dictionary: ["DEVELOPMENT_TEAM": teamId]),
        sources: [TargetSource(path: sourcesDirectory.path)],
        info: Plist(path: infoPlistFile.path)
      )

      let project = Project(
        basePath: Path(projectDirectory.path),
        name: "Dummy",
        targets: [target],
        settings: Settings(dictionary: ["DEVELOPMENT_TEAM": teamId]),
        options: SpecOptions(bundleIdPrefix: bundleIdentifierPrefix)
      )

      return (project, productName)
    }
  #endif
}

extension NonMacAppleOS {
  #if SUPPORT_XCODEPROJ
    fileprivate var xcodePlatform: ProjectSpec.Platform {
      switch self {
        case .iOS:
          return .iOS
        case .tvOS:
          return .tvOS
        case .visionOS:
          return .visionOS
      }
    }
  #endif
}
