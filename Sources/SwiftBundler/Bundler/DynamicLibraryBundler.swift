import Foundation

/// A utility for copying dynamic libraries into an app bundle and updating the app executable's rpaths accordingly.
enum DynamicLibraryBundler {
  /// Copies the dynamic libraries within a build's products directory to an
  /// output directory.
  ///
  /// The app's executable's rpath is updated to reflect the new relative
  /// location of each dynamic library.
  /// - Parameters:
  ///   - appExecutable: The app executable to update the rpaths of.
  ///   - libraryDirectory: The directory to copy plain dynamic libraries to.
  ///   - frameworkDirectory: The directory to copy frameworks to.
  ///   - productsDirectory: The build's products directory (used to locate
  ///     dynamic libraries that aren't installed system wide).
  ///   - isXcodeBuild: If `true` the `PackageFrameworks` subdirectory will be
  ///     searched for frameworks containing dynamic libraries instead.
  ///   - universal: Whether the build is a universal build or not. Only true if
  ///     the build is a SwiftPM build and universal.
  ///   - makeStandAlone: If `true`, all non-system dynamic libraries depended
  ///     on by the executable will be moved into the app bundle, and relevant
  ///     rpaths will be updated accordingly.
  static func copyDynamicDependencies(
    dependedOnBy appExecutable: URL,
    toLibraryDirectory libraryDirectory: URL,
    orFrameworkDirectory frameworkDirectory: URL,
    productsDirectory: URL,
    isXcodeBuild: Bool,
    universal: Bool,
    makeStandAlone: Bool
  ) async throws(Error) {
    log.info("Copying dynamic libraries")

    try await copyDynamicDependencies(
      dependedOnBy: appExecutable,
      toLibraryDirectory: libraryDirectory,
      orFrameworkDirectory: frameworkDirectory,
      productsDirectory: productsDirectory,
      includeSystemWideDependencies: makeStandAlone
    )

    // Update the app's rpaths
    var arguments: [String] = []
    if universal || isXcodeBuild {
      arguments += ["-delete_rpath", "@executable_path/../lib"]
    }

    let existingRPaths = try await rpaths(of: appExecutable)
    let executableDirectory = appExecutable.deletingLastPathComponent()
    for directory in [frameworkDirectory, libraryDirectory] {
      let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
      guard contents?.isEmpty == false else {
        continue
      }

      let relativePath = directory.path(relativeTo: executableDirectory)
        .split(separator: "/")
        .filter { $0 != "." }
        .joined(separator: "/")
      let rpath = "@executable_path/\(relativePath)"
      if !existingRPaths.contains(rpath) {
        arguments += ["-add_rpath", rpath]
      }
    }

    guard !arguments.isEmpty else {
      return
    }

    let process = Process.create(
      "/usr/bin/install_name_tool",
      arguments: arguments + [appExecutable.path]
    )

    do {
      try await process.runAndWait()
    } catch {
      throw Error(.failedToUpdateAppRPaths(binary: appExecutable), cause: error)
    }
  }

  /// Gets the rpaths of a binary.
  private static func rpaths(of binary: URL) async throws(Error) -> [String] {
    let otoolOutput: String
    let process = Process.create("/usr/bin/otool", arguments: ["-l", binary.path])
    do {
      otoolOutput = try await process.getOutput()
    } catch {
      throw Error(.failedToEnumerateRPaths(binary: binary), cause: error)
    }

    // Each LC_RPATH command is followed by its size and then its path
    let lines = otoolOutput.split(separator: "\n").map { line in
      line.trimmingCharacters(in: .whitespaces)
    }
    return lines.indices.compactMap { index in
      guard lines[index] == "cmd LC_RPATH", index + 2 < lines.count else {
        return nil
      }
      return lines[index + 2].dropFirst("path ".count)
        .components(separatedBy: " (offset")
        .first
    }
  }

  /// Copies all dynamic libraries depended on by `binary`, an executable or
  /// dynamic library, to the specified directory. Updates the install names
  /// all dependencies and recursively copies the dependencies of each
  /// dependency as well.
  /// - Parameters:
  ///   - binary: The executable or dynamic library to copy the dependencies of.
  ///   - libraryDirectory: The directory to copy plain dynamic libraries to.
  ///   - frameworkDirectory: The directory to copy frameworks to.
  ///   - productsDirectory: The products directory produced by SwiftPM or Xcode.
  ///     Used to construct search paths.
  ///   - includeSystemWideDependencies: Enables an experimental mode in which
  ///     system-wide dependencies are also copied. This can be used to distribute
  ///     apps which rely on system dependencies such as Gtk, or on newer Swift
  ///     runtime features, but it's still quite flakey.
  static func copyDynamicDependencies(
    dependedOnBy binary: URL,
    toLibraryDirectory libraryDirectory: URL,
    orFrameworkDirectory frameworkDirectory: URL,
    productsDirectory: URL,
    includeSystemWideDependencies: Bool
  ) async throws(Error) {
    let dynamicDependencies = try await enumerateDynamicDependencies(of: binary)

    let uninterestingPrefixes = ["/usr/lib/", "/System/Library/"]
    let filteredDependencies = dynamicDependencies
      .filter { path in
        !uninterestingPrefixes.contains { prefix in
          path.starts(with: prefix)
        }
      }
      .filter { installName in
        return (
          installName.starts(with: rpathPrefix)
          // Due to concurrency back deployment, the concurrency runtime install name
          // is relative to the rpath, so we need a special case to exclude it.
          && installName != "@rpath/libswift_Concurrency.dylib"
          && installName != "@rpath/libswiftCompatibilitySpan.dylib"
        ) || includeSystemWideDependencies
      }

    for installName in filteredDependencies {
      try await copyDynamicDependency(
        dependedOnBy: binary,
        toLibraryDirectory: libraryDirectory,
        orFrameworkDirectory: frameworkDirectory,
        installName: installName,
        productsDirectory: productsDirectory,
        includeSystemWideDependencies: includeSystemWideDependencies
      )
    }
  }

  /// Updates the install name of a library that has changed locations relative
  /// to the executable.
  /// - Parameters:
  ///   - library: The library's name.
  ///   - executable: The executable to update the install name in.
  ///   - originalLibraryLocation: The library's original location.
  ///   - newLibraryLocation: The library's new location.
  ///   - librarySearchDirectory: The original place that the executable would've
  ///     searched for libraries.
  static func updateLibraryInstallName(
    of library: String,
    in executable: URL,
    originalLibraryLocation: URL,
    newLibraryLocation: URL,
    librarySearchDirectory: URL
  ) async throws(Error) {
    let originalRelativePath = originalLibraryLocation.path(
      relativeTo: librarySearchDirectory
    )
    let newRelativePath = newLibraryLocation.path(
      relativeTo: executable.deletingLastPathComponent()
    )

    try await updateLibraryInstallName(
      in: executable,
      original: "@rpath/\(originalRelativePath)",
      new: "@rpath/\(newRelativePath)"
    )
  }

  /// Updates the install name of a library that has been moved.
  /// - Parameters:
  ///   - binary: The binary to update the install name in.
  ///   - originalInstallName: The library's original install name.
  ///   - newInstallName: The library's new install name.
  static func updateLibraryInstallName(
    in binary: URL,
    original originalInstallName: String,
    new newInstallName: String
  ) async throws(Error) {
    let process = Process.create(
      "/usr/bin/install_name_tool",
      arguments: [
        "-change",
        originalInstallName,
        newInstallName,
        binary.path,
      ]
    )

    do {
      try await process.runAndWait()
    } catch {
      throw ErrorMessage.failedToUpdateLibraryInstallName(
        binary: binary,
        original: originalInstallName,
        new: newInstallName
      ).becauseOf(error)
    }
  }

  private static func enumerateDynamicDependencies(
    of binary: URL
  ) async throws(Error) -> [String] {
    let otoolOutput: String
    let process = Process.create("/usr/bin/otool", arguments: ["-L", binary.path])
    do {
      otoolOutput = try await process.getOutput()
    } catch {
      throw ErrorMessage.failedToEnumerateDynamicDependencies(
        binary: binary
      ).becauseOf(error)
    }

    let dependencies = otoolOutput.split(separator: "\n")
      .dropFirst()
      .map { (line: Substring) -> String in
        // We find the first opening parenthesis from starting from the end of
        // the string in case the install name contains an open parenthesis.
        let installName = line.dropFirst()
          .reversed()
          .split(separator: "(", maxSplits: 1)[1]
          .reversed()

        return String(installName)
          .trimmingCharacters(in: .whitespaces)
      }

    return dependencies
  }

  private static let rpathPrefix = "@rpath/"

  private static func locateDynamicDependency(
    installName: String,
    productsDirectory: URL
  ) throws(Error) -> URL {
    if installName.starts(with: rpathPrefix) {
      // TODO: Expand this logic to load search path from binary if possible (so that this
      //   doesn't break when an upstream tool changes something in the future).
      let searchPath = [
        productsDirectory,
        productsDirectory / "PackageFrameworks",
      ]
      let relativePath = String(installName.dropFirst(rpathPrefix.count))
      let locations = searchPath.map { $0 / relativePath }

      guard let location = locations.first(where: { $0.exists() }) else {
        throw RichError(.failedToLocateDynamicDependency(installName: installName))
      }

      return location
    } else {
      return URL(fileURLWithPath: installName)
    }
  }

  private static func copyDynamicDependency(
    dependedOnBy binary: URL,
    toLibraryDirectory libraryDirectory: URL,
    orFrameworkDirectory frameworkDirectory: URL,
    installName: String,
    productsDirectory: URL,
    includeSystemWideDependencies: Bool
  ) async throws(Error) {
    let location = try locateDynamicDependency(
      installName: installName,
      productsDirectory: productsDirectory
    )
    let dylibLocation = location.resolvingSymlinksInPath()

    // Discover whether the dylib is from a framework or not
    var framework = dylibLocation
    var isFramework = false
    while framework.path != "/" {
      if framework.pathExtension == "framework" {
        isFramework = true
        break
      }
      framework = framework.deletingLastPathComponent()
    }

    let dependency = isFramework ? framework : dylibLocation

    // Compute output location
    let targetDirectory = isFramework ? frameworkDirectory : libraryDirectory
    var outputDependency = targetDirectory / dependency.lastPathComponent
    if !isFramework && outputDependency.pathExtension == "" {
      // Add `.dylib` path extension when copying (if not already present) so that the
      // code signer can easily locate all dylibs to sign.
      outputDependency = outputDependency.appendingPathExtension("dylib")
    }

    // Update the install name of the dylib to be relative to the app's rpaths
    let pathInFramework = dylibLocation.pathComponents
      .dropFirst(framework.pathComponents.count)
      .joined(separator: "/")
    let outputDylib = isFramework ? outputDependency / pathInFramework : outputDependency
    let newInstallName = isFramework
      ? "@rpath/\(outputDependency.lastPathComponent)/\(pathInFramework)"
      : "@rpath/\(outputDependency.lastPathComponent)"
    if newInstallName != installName {
      try await updateLibraryInstallName(in: binary, original: installName, new: newInstallName)
    }

    // Avoid copying libraries twice
    guard !outputDependency.exists() else {
      return
    }

    // Copy the library
    try Error.catch {
      try FileManager.default.copyItem(
        at: dependency,
        to: outputDependency
      )
    }

    // Frameworks from xcframework binary targets are copied out of SwiftPM's
    // read-only dependency checkouts, so we need to make the copy writable
    // before we can update its install names or sign it.
    try makeWritable(outputDependency)

    // Recursively copy the dependencies of this library's dependencies.
    try await copyDynamicDependencies(
      dependedOnBy: outputDylib,
      toLibraryDirectory: libraryDirectory,
      orFrameworkDirectory: frameworkDirectory,
      productsDirectory: productsDirectory,
      includeSystemWideDependencies: includeSystemWideDependencies
    )
  }

  /// Makes a file or a directory and all of its contents writable by its owner.
  /// - Parameter location: The file or directory to make writable.
  private static func makeWritable(_ location: URL) throws(Error) {
    var items = [location]
    if let enumerator = FileManager.default.enumerator(
      at: location,
      includingPropertiesForKeys: [.isSymbolicLinkKey]
    ) {
      for case let item as URL in Array(enumerator) {
        items.append(item)
      }
    }

    try Error.catch(withMessage: .failedToMakeLibraryWritable(library: location)) {
      for item in items {
        // skip symlinks
        let values = try item.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
          continue
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: item.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o644
        try FileManager.default.setAttributes(
          [.posixPermissions: NSNumber(value: permissions | 0o200)],
          ofItemAtPath: item.path
        )
      }
    }
  }
}
