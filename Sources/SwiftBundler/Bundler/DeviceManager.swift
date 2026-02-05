import Foundation
import ErrorKit

enum DeviceManager {
  /// Only works on macOS.
  static func listDestinations() async throws(Error) -> [Device] {
    let dummyProject =
      FileManager.default.temporaryDirectory
      / "dev.stackotter.swift-bundler/SwiftBundlerDummyPackage"
    let dummyProjectName = "Dummy"

    do {
      if dummyProject.exists() {
        try FileManager.default.removeItem(at: dummyProject)
      }

      try FileManager.default.createDirectory(at: dummyProject)

      try await SwiftPackageManager.createPackage(
        in: dummyProject,
        name: dummyProjectName,
        toolchain: nil
      )
    } catch {
      throw Error(.failedToCreateDummyProject)
    }

    let output = try await Error.catch(withMessage: .failedToListXcodeDestinations) {
      try await Process.create(
        "xcodebuild",
        arguments: [
          "-showdestinations", "-scheme", dummyProjectName,
        ],
        directory: dummyProject
      ).getOutput()
    }

    let lines = output.split(
      separator: "\n",
      omittingEmptySubsequences: false
    ).map(String.init)

    guard
      let startIndex =
        lines.firstIndex(
          of: "\tAvailable destinations for the \"\(dummyProjectName)\" scheme:"
        )?.advanced(by: 1),
      let endIndex = lines[startIndex...].firstIndex(of: "")
    else {
      throw Error(
        .failedToParseXcodeDestinationList(
          output,
          reason: "Couldn't locate destination section in output"
        )
      )
    }

    return try Array(lines[startIndex..<endIndex])
      .compactMap(parseXcodeDestination)
  }

  /// Returns nil if the line represents a device that Swift Bundler doesn't
  /// support.
  private static func parseXcodeDestination(
    _ line: String
  ) throws(Error) -> Device? {
    var index = line.startIndex
    var dictionary: [String: String] = [:]

    while index < line.endIndex, line[index].isWhitespace {
      index = line.index(after: index)
      continue
    }

    func failure(_ reason: String) -> Error {
      Error(.failedToParseXcodeDestination(line, reason: reason))
    }

    func read(_ count: Int) -> String? {
      let endIndex = line.index(index, offsetBy: count)
      if endIndex <= line.endIndex {
        let result = String(line[index..<endIndex])
        index = endIndex
        return result
      } else {
        return nil
      }
    }

    func readUntil(oneOf characters: Set<Character>) throws(Error) -> String {
      var endIndex = index
      while endIndex != line.endIndex, !characters.contains(line[endIndex]) {
        endIndex = line.index(after: endIndex)
      }

      guard endIndex != line.endIndex else {
        let characterList = characters.map { "'\($0)'" }.joined(separator: ", ")
        throw failure(
          "Expected to encounter one of [\(characterList)] but got end of line"
        )
      }

      let startIndex = index
      index = endIndex
      return String(line[startIndex..<endIndex])
    }

    func expect(_ pattern: String) throws(Error) {
      let startIndex = index
      guard let slice = read(pattern.count) else {
        throw failure(
          """
          Expected '\(pattern)' at index \(startIndex.offset(in: line)), but \
          got end of line
          """
        )
      }
      guard pattern == slice else {
        throw failure(
          """
          Expected '\(pattern)' at index \(startIndex.offset(in: line)), but \
          got '\(slice)'
          """
        )
      }
    }

    try expect("{ ")

    while line[index] != "}" {
      let key = try readUntil(oneOf: [":"])
      try expect(":")

      var value = try readUntil(oneOf: ["[", ",", "}"])
      if line[index] == "[" {
        // We have to handle a horrid edge case because one of the Mac
        // targets usually has the 'variant' field set to
        // 'Designed for [iPad, iPhone]', which contains a comma and
        // messes everything up. We could technically make a smarter
        // parser that can handle that specific case without making it
        // an edge case, but given that this format isn't even a proper
        // data format, Apple's probably always gonna cook up a few more
        // edge cases, so I don't think it'd be worth it.
        let bracketedContent = try readUntil(oneOf: ["]"])
        let trailingContent = try readUntil(oneOf: [",", "}"])

        value += bracketedContent + trailingContent
      }

      if line[index] == "}" {
        // Remove trailing space
        value = String(value.dropLast())
      }

      // Skip space between each key-value pair
      if index < line.endIndex, line[index] == "," {
        index = line.index(index, offsetBy: 2)
      }

      dictionary[key] = value
    }

    try expect("}")

    guard let platform = dictionary["platform"] else {
      throw failure("Missing platform")
    }

    let variant = dictionary["variant"]
    guard let parsedPlatform = ApplePlatform.parseXcodeDestinationName(platform, variant) else {
      // Skip devices for platforms that we don't handle, such as DriverKit
      return nil
    }

    guard let id = dictionary["id"] else {
      // Skip generic destinations without ids
      return nil
    }

    guard !id.hasSuffix(":placeholder") else {
      // Skip generic destinations with ids
      return nil
    }

    guard let name = dictionary["name"] else {
      throw failure("Missing name")
    }

    return Device(
      applePlatform: parsedPlatform,
      name: name,
      id: id,
      status: dictionary["error"].map(ConnectedAppleDevice.Status.unavailable)
        ?? .available
    )
  }

  static func resolve(
    specifier: String,
    platform: Platform?
  ) async throws(Error) -> Device {
    guard specifier != "host" else {
      if platform == nil || platform == HostPlatform.hostPlatform.platform {
        return .host(HostPlatform.hostPlatform)
      } else {
        throw Error(.deviceNotFound(specifier: specifier, platform: platform))
      }
    }

    guard HostPlatform.hostPlatform == .macOS else {
      throw Error(.deviceNotFound(specifier: specifier, platform: platform))
    }

    let devices = try await listDestinations().sorted { first, second in
      // Physical devices first (since --simulator can be used to
      // disambiguate simulators) and put shorter names first (otherwise
      // there'd be no guarantee the "iPhone 15" matches "iPhone 15" when
      // both "iPhone 15" and "iPhone 15 Pro" exist, and you'd be left with
      // no way to disambiguate). Also put available devices above
      // unavailable ones.
      switch (first, second) {
        case (.host, .connectedAppleDevice):
          return false
        case (.connectedAppleDevice(let first), .connectedAppleDevice(let second)):
          if first.platform.isSimulator && !second.platform.isSimulator {
            return false
          } else if first.name.count > second.name.count {
            return false
          } else if second.status == .available && first.status != .available {
            return false
          } else {
            return true
          }
        default:
          return true
      }
    }

    if let device = devices.first(where: { $0.id == specifier }) {
      guard platform == nil || device.platform == platform else {
        throw Error(.deviceNotFound(specifier: specifier, platform: platform))
      }
      return device
    }

    let matches = devices.filter { device in
      // Filter by platform if provided
      if let platform = platform {
        return device.platform == platform
      } else {
        return true
      }
    }.filter { device in
      device.description.contains(specifier)
    }

    guard let match = matches.first else {
      throw Error(.deviceNotFound(specifier: specifier, platform: platform))
    }

    if matches.count > 1 {
      log.warning(
        "Multiple devices matched '\(specifier)', using \(match.description)"
      )
    }

    return match
  }
}
