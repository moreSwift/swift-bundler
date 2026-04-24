import Foundation
import Version
import Parsing

/// A bundler targeting Android.
enum APKBundler: Bundler {
  static let outputIsRunnable = true
  static let requiresBuildAsDylib = true

  typealias Context = Void

  static func computeContext(
    context: BundlerContext,
    command: BundleCommand,
    manifest: PackageManifest
  ) throws(Error) {}

  static func intendedOutput(
    in context: BundlerContext,
    _ additionalContext: Context
  ) -> BundlerOutputStructure {
    let bundle = context.outputDirectory / "\(context.appName).apk"
    return BundlerOutputStructure(
      bundle: bundle,
      executable: bundle
    )
  }

  static func checkHostCompatibility() throws(Error) {
    // Ref: https://github.com/android/ndk/issues/1752
    guard BuildArchitecture.host == .x86_64 || HostPlatform.hostPlatform == .macOS else {
      throw Error(.hostRequiresX86_64Compatibility)
    }
  }

  /// Computes the Android package identifier to give an app based off its
  /// Swift Bundler app identifier.
  static func computePackageIdentifier(
    forAppIdentifier appIdentifier: String
  ) -> String {
    appIdentifier.lowercased()
  }

  static func bundle(
    _ context: BundlerContext,
    _ additionalContext: Context
  ) async throws(Error) -> BundlerOutputStructure {
    let outputAPK = intendedOutput(in: context, additionalContext).bundle
    let appBundleName = outputAPK.lastPathComponent

    log.info("Bundling '\(appBundleName)'")

    // Locate Android SDK
    let androidSDK = try Error.catch {
      try AndroidSDKManager.locateAndroidSDK()
    }

    let defaultCompilationSDKVersion = try Error.catch {
      try AndroidSDKManager.getDefaultCompilationSDKVersion(forSDK: androidSDK)
    }

    // Create project structure.
    let identifier = context.appConfiguration.identifier
    let projectDirectory = context.outputDirectory / "\(context.appName).project"
    let project = ProjectStructure(at: projectDirectory, forAppWithIdentifier: identifier)

    if project.root.exists() {
      try Error.catch {
        try FileManager.default.removeItem(at: project.root)
      }
    }
    try project.createDirectories()

    // Create gradle wrapper files
    let gradlew = Data(PackageResources.gradlew)
    let gradleWrapperJar = Data(PackageResources.gradle_wrapper_jar)
    let gradleWrapperProperties = generateGradleWrapperProperties()
    let gradleLibsVersions = generateGradleLibsVersions()
    try Error.catch(withMessage: .failedToCreateGradleWrapperFiles) {
      try gradlew.write(to: project.gradlew)
      try gradleWrapperJar.write(to: project.gradleWrapperJar)
      try gradleWrapperProperties.write(to: project.gradleWrapperProperties)
      try gradleLibsVersions.write(to: project.gradleLibsVersionsFile)

      // Add executable permission
      try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(0o755)],
        ofItemAtPath: project.gradlew.path
      )
      try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(0o755)],
        ofItemAtPath: project.gradleWrapperJar.path
      )
    }

    // We use the platform version instead of the minSDK from appConfiguration
    // because it's more directly the value we want. E.g. if Swift manifests
    // ever support specifying an Android API version, or if we ever support
    // loading the Android API version from Android-specific configuration files,
    // then the meanings of platformVersion and appConfiguration.android.minSDK
    // would diverge, and platformVersion would be the one we want.
    guard
      let platformVersion = context.platformVersion,
      let minSDK = Int(platformVersion)
    else {
      log.debug("platformVersion: \(context.platformVersion.debugDescription)")
      throw Error(.cannotBuildAPKWithoutTargetAndroidPlatformVersion)
    }

    let compileSDK = context.appConfiguration.android?.compileSDK
      ?? defaultCompilationSDKVersion.major
    let targetSDK = context.appConfiguration.android?.targetSDK
      ?? compileSDK

    let versionCode: Int
    if let providedVersionCode = context.appConfiguration.android?.versionCode {
      versionCode = providedVersionCode
    } else {
      do {
        let revision = try await Error.catch {
          try await Git.countRevisions(context.packageDirectory)
        }
        versionCode = revision
      } catch {
        versionCode = 1
      }
    }

    guard let swiftSDK = context.swiftSDK else {
      throw Error(.cannotBundleAPKWithoutSwiftAndroidSDK)
    }

    let ndk = try Error.catch {
      guard let ndk = try SwiftSDKManager.getLinkedNDK(fromAndroidSDK: swiftSDK) else {
         log.warning(
          """
          Failed to retrieve linked NDK from Swift Android SDK; falling back to latest NDK
          """
        )
        return try AndroidSDKManager.getLatestNDK(availableIn: androidSDK)       
      }

      return ndk
    }

    let ndkVersion = try Error.catch {
      try AndroidSDKManager.getVersion(ofNDKAt: ndk)
    }

    // Create Gradle configuration files
    let packageIdentifier = computePackageIdentifier(
      forAppIdentifier: context.appConfiguration.identifier
    )
    let gradleBuildConfig = generateGradleBuildConfig(
      packageIdentifier: packageIdentifier,
      appVersion: context.appConfiguration.version,
      versionCode: versionCode,
      minSDK: minSDK,
      targetSDK: targetSDK,
      compileSDK: compileSDK,
      architectures: context.architectures,
      projectStructure: project,
      ndkVersion: ndkVersion
    )
    let gradleSettings = generateGradleSettings(forApp: context.appName)
    let gradleProperties = generateGradleProperties()
    let localProperties = generateLocalProperties(androidSDK: androidSDK)

    let themeName = "AppTheme"
    let parentTheme = "Theme.Material3.DayNight.NoActionBar"
    let appNameStringKey = "app_name"
    let androidManifest = generateAndroidManifest(
      targetAPI: targetSDK,
      themeName: themeName,
      appNameStringKey: appNameStringKey,
      projectStructure: project
    )

    let cmakeLists = generateCMakeLists(product: context.appConfiguration.product)

    try Error.catch(withMessage: .failedToCreateGradleConfigurationFiles) {
      try gradleBuildConfig.write(to: project.gradleBuildConfig)
      try gradleSettings.write(to: project.gradleSettings)
      try gradleProperties.write(to: project.gradleProperties)
      try localProperties.write(to: project.localProperties)
      try androidManifest.write(to: project.androidManifest)
      try cmakeLists.write(to: project.cmakeLists)
    }

    // Generate source code files
    let mainActivity = generateMainActivity(packageIdentifier: packageIdentifier)
    let shimSource = generateShimSource(
      packageIdentifier: packageIdentifier,
      swiftEntryPoint: "AndroidBackend_entrypoint",
      projectStructure: project
    )
    let shimHeader = generateShimHeader(
      packageIdentifier: packageIdentifier,
      mainActivityName: project.mainActivityName
    )

    try Error.catch(withMessage: .failedToCreateGradleProjectSourceFiles) {
      try mainActivity.write(to: project.mainActivitySource)
      try shimSource.write(to: project.shimSource)
      try shimHeader.write(to: project.shimHeader)
    }

    if let iconPath = context.appConfiguration.icon {
      let icon = context.packageDirectory / iconPath
      do {
        try FileManager.default.copyItem(at: icon, to: project.icon)
      } catch {
        throw Error(.failedToCopyIcon(source: icon, destination: project.icon), cause: error)
      }
    } else {
      let iconData = Data(PackageResources.DefaultAndroidIcon_webp)
      try Error.catch(withMessage: .failedToCreateDefaultIcon(project.icon)) {
        try iconData.write(to: project.icon)
      }
    }

    // Generate resource files
    let themesXML = generateThemesXML(themeName: themeName, parentTheme: parentTheme)
    let nightThemesXML = generateNightThemesXML(themeName: themeName, parentTheme: parentTheme)
    let stringsXML = generateStringsXML(
      appName: context.appName,
      appNameStringKey: appNameStringKey
    )
    try Error.catch(withMessage: .failedToCreateGradleProjectResourceFiles) {
      try themesXML.write(to: project.themesFile)
      try nightThemesXML.write(to: project.nightThemesFile)
      try stringsXML.write(to: project.stringsFile)
    }

    guard
      let architecture = context.architectures.first,
      context.architectures.count == 1
    else {
      // TODO(stackotter): Will require bundle context to support having one
      //   product directory per architecture.
      throw Error(.multiArchitectureBuildsNotSupported)
    }

    let jniLibs = project.jniLibsSubdirectory(for: architecture)
    let library = context.productsDirectory / "lib\(context.appConfiguration.product).so"
    let libraryDestination = jniLibs / library.lastPathComponent
    do {
      try FileManager.default.createDirectory(at: jniLibs)
      try FileManager.default.copyItem(at: library, to: libraryDestination)
    } catch {
      let message = ErrorMessage.failedToCopyExecutable(
        source: library,
        destination: libraryDestination
      )
      throw Error(message, cause: error)
    }

    let readelfTool = try Error.catch {
      try AndroidSDKManager.locateReadelfTool(
        inNDK: ndk,
        hostPlatform: .hostPlatform,
        hostArchitecture: .host
      )
    }

    let subdirectory = switch architecture {
      case .arm64:
        "aarch64-linux-android"
      case .armv7:
        "arm-linux-androideabi"
      case .x86_64:
        "x86_64-linux-android"
      case .x86:
        "x86-linux-android"
    }

    let androidLibrarySearchDirectories = [
      DynamicLibrarySearchDirectory(context.productsDirectory),
      DynamicLibrarySearchDirectory(swiftSDK.resourcesDirectory / "android"),
    ] + swiftSDK.librarySearchDirectories.flatMap { searchDirectory in
      // TODO: Is this the standard way that Swift uses the library search
      //   directory? The directory itself is just a bunch of triple-specific
      //   subdirectories which seems a bit strange.
      [
        DynamicLibrarySearchDirectory(
          searchDirectory / subdirectory,
          requiresCopying: true
        ),
        DynamicLibrarySearchDirectory(
          searchDirectory / subdirectory / String(minSDK),
          requiresCopying: false
        ),
      ]
    }

    let dynamicDependencies = try await enumerateRecursiveDynamicDependencies(
      ofLibrary: library,
      readelfTool: readelfTool,
      searchDirectories: androidLibrarySearchDirectories
    )

    for dependency in dynamicDependencies where dependency.copy {
      let destination = jniLibs / dependency.location.lastPathComponent
      try Error.catch(withMessage: .failedToCopyDynamicDependency(dependency.location)) {
        try FileManager.default.copyItem(at: dependency.location, to: destination)
      }
    }

    // Locate and copy Java/Kotlin sources
    log.info("Locating and copying Java/Kotlin sources")
    try copyJavaAndKotlinSources(
      dependedOnByRootProduct: context.appConfiguration.product,
      fromPackageGraph: context.packageGraph,
      toJavaSources: project.javaSourceDirectory,
      targetPlatform: context.platform
    )

    // Run Gradle build
    let task = "assembleDebug"
    var gradleArguments = [task]
    if log.logLevel <= .debug {
      gradleArguments.append("--debug")
    }
    let process = Process.create(
      project.gradlew.path,
      arguments: gradleArguments,
      directory: project.root,
      runSilentlyWhenNotVerbose: false
    )
    let inputPipe = Pipe()
    process.standardInput = inputPipe

    log.info("Running gradle \(task) task")
    try await Error.catch {
      // If we don't close the writing end of stdin, then gradlew hangs for reasons
      // unknown to me. It seems related to gradle having interactive output, but
      // even with '--console=plain' the process hangs after supposedly finishing
      // the build (and logging everything). Without a plain console, it hangs around
      // when it first tries doing interactive output (afaict).
      try inputPipe.fileHandleForWriting.close()

      try await process.runAndWait()
    }

    // Copy APK to output location
    let apk = project.root / "build/outputs/apk/debug/\(context.appName)-debug.apk"
    try Error.catch(withMessage: .failedToCopyAPK(apk, outputAPK)) {
      try FileManager.default.copyItem(at: apk, to: outputAPK)
    }

    return BundlerOutputStructure(
      bundle: outputAPK,
      executable: outputAPK
    )
  }

  /// Copies Java and Kotlin sources from the given package graph to a Gradle
  /// project's Java sources directory.
  ///
  /// Java and Kotlin sources not in directories prescribed by corresponding
  /// ``TargetConfiguration/Android/javaDirectory`` or
  /// ``TargetConfiguration/Android/kotlinDirectory`` configuration values are
  /// ignored.
  /// - Parameters:
  ///   - product: The root product to begin from when recursively searching for
  ///     Java and Kotlin sources. The product is assumed to be in the package
  ///     graph's root package.
  ///   - packageGraph: The source package graph.
  ///   - sourcesDirectory: The output sources directory.
  private static func copyJavaAndKotlinSources(
    dependedOnByRootProduct product: String,
    fromPackageGraph packageGraph: SwiftPackageManager.PackageGraph,
    toJavaSources sourcesDirectory: URL,
    targetPlatform: Platform
  ) throws(Error) {
    let conditionalTargets = try Error.catch {
      try packageGraph.transitiveTargets(
        inProduct: product,
        inPackage: packageGraph.rootPackage.reference
      )
    }

    let targets = packageGraph.activeTargets(
      inConditionalReferences: conditionalTargets,
      withTargetPlatform: targetPlatform
    )

    var directories: [(
      location: URL,
      target: SwiftPackageManager.TargetReference,
      fileExtension: String
    )] = []

    for target in targets {
      guard let configuration = try Error.catch(do: {
        try packageGraph.configuration(ofTarget: target)
      }) else {
        continue
      }

      let targetInfo = try Error.catch {
        try packageGraph.target(referredToBy: target)
      }

      let javaDirectory = configuration.android?.javaDirectory
      let kotlinDirectory = configuration.android?.kotlinDirectory ?? javaDirectory
      if let javaDirectory {
        log.info("Target '\(target.name)' has Java sources")
        directories.append((targetInfo.directory / javaDirectory, target, "java"))
      }
      if let kotlinDirectory {
        log.info("Target '\(target.name)' has Kotlin sources")
        directories.append((targetInfo.directory / kotlinDirectory, target, "kt"))
      }
    }

    for (directory, target, fileExtension) in directories {
      guard let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: nil
      ) else {
        throw Error(.failedToEnumerateJVMSources(directory, target))
      }


      var files: [URL] = []
      for item in enumerator {
        guard
          let file = item as? URL,
          file.exists(withType: .file),
          file.pathExtension == fileExtension
        else {
          continue
        }
        
        files.append(file)
      }

      for file in files {
        let destination = sourcesDirectory / file.path(relativeTo: directory)

        let destinationDirectory = destination.deletingLastPathComponent()
        if !destinationDirectory.exists() {
          try Error.catch {
            try FileManager.default.createDirectory(
              at: destinationDirectory,
              withIntermediateDirectories: true
            )
          }
        }

        if destination.exists() {
          var clashes: [SwiftPackageManager.TargetReference] = []
          for (otherDirectory, otherTarget, otherFileExtension) in directories {
            guard otherFileExtension == fileExtension else { continue }

            if (otherDirectory / file.relativePath).exists(withType: .file) {
              clashes.append(otherTarget)
            }
          }
          
          log.warning(
            """
            Java/Kotlin source file at '\(file.relativePath)' will be overwritten \
            by file of same name from target '\(target.name)' in package with \
            identity '\(target.package.identity)'; clashing targets: \(
              clashes.map { "\($0.name) in \($0.package)" }.joinedGrammatically()
            )
            """
          )
        }

        try Error.catch(
          withMessage: .failedToCopyJVMSource(source: file, destination: destination)
        ) {
          try FileManager.default.copyItem(at: file, to: destination)
        }
      }
    }
  }

  struct SharedObject: Hashable {
    /// The location of the shared object.
    var location: URL
    /// Whether or not the shared object should be copied into the bundle.
    ///
    /// `false` generally means that the library is shipped with the system.
    var copy: Bool
  }

  struct DynamicLibrarySearchDirectory {
    /// The directory to search.
    var location: URL
    /// Whether or not libraries found in this location should be copied into
    /// the application's bundle. `false` generally means that the libraries in
    /// this directory are shipped with the system.
    var requiresCopying: Bool

    init(_ location: URL, requiresCopying: Bool = true) {
      self.location = location
      self.requiresCopying = requiresCopying
    }
  }

  private static func enumerateRecursiveDynamicDependencies(
    ofLibrary library: URL,
    readelfTool: URL,
    searchDirectories: [DynamicLibrarySearchDirectory]
  ) async throws(Error) -> [SharedObject] {
    var queue = [library]
    var seen: Set<SharedObject> = []
    var dependencies: [SharedObject] = []

    while let library = queue.popLast() {
      let libraryDependencies = try await enumerateDynamicDependencies(
        ofLibrary: library,
        readelfTool: readelfTool,
        searchDirectories: searchDirectories
      )

      for dependency in libraryDependencies {
        guard seen.insert(dependency).inserted else {
          continue
        }

        dependencies.append(dependency)
        queue.append(dependency.location)
      }
    }

    return dependencies
  }

  private static func enumerateDynamicDependencies(
    ofLibrary library: URL,
    readelfTool: URL,
    searchDirectories: [DynamicLibrarySearchDirectory]
  ) async throws(Error) -> [SharedObject] {
    let process = Process.create(
      readelfTool.path,
      arguments: ["-d", library.path]
    )

    let output: String
    do {
      output = try await process.getOutput()
    } catch {
      throw Error(.failedToEnumerateDynamicDependenciesOfLibrary(library), cause: error)
    }

    let lines = output.split(separator: "\n").dropFirst(2)
    let parser = Parse(input: Substring.self) {
      Skip {
        Whitespace()
        "0x"
        Int.parser(radix: 16)
        Whitespace()
        "(NEEDED)"
        Whitespace()
        "Shared library: ["
      }
      PrefixUpTo("]")
      Skip {
        Rest()
      }
    }

    var dependencyNames: [String] = []
    for line in lines {
      guard let libraryName = try? parser.parse(line) else {
        continue
      }
      dependencyNames.append(String(libraryName))
    }

    var dependencies: [SharedObject] = []
    for dependencyName in dependencyNames {
      let guesses = searchDirectories.map { directory in
        SharedObject(
          location: directory.location / dependencyName,
          copy: directory.requiresCopying
        )
      }
      guard let dependency = guesses.first(where: { $0.location.exists() }) else {
        throw Error(.failedToLocateDynamicDependencyOfLibrary(
          library,
          dependencyName: dependencyName,
          guesses: guesses.map(\.location)
        ))
      }

      dependencies.append(dependency)
    }

    return dependencies
  }

  private static func generateGradleBuildConfig(
    packageIdentifier: String,
    appVersion: Version,
    versionCode: Int,
    minSDK: Int,
    targetSDK: Int,
    compileSDK: Int,
    architectures: [BuildArchitecture],
    projectStructure: ProjectStructure,
    ndkVersion: Version
  ) -> String {
    let architectureNames = architectures.map(\.androidABIName)
    let abiFilters = architectureNames.map { architecture in
      "\"\(architecture)\""
    }.joined(separator: ", ")
    let keepDebugSymols = architectureNames.map { architecture in
      "            keepDebugSymbols += \"\(architecture)/*.so\""
    }.joined(separator: "\n")

    let cmakePath = projectStructure.cmakeLists.path(relativeTo: projectStructure.root)

    let cmake16KBAlignmentFix: String
    if ndkVersion.major == 27 {
      // Support 16kb page sizes. This is supported by default for NDK >=28
      cmake16KBAlignmentFix = """

                externalNativeBuild {
                    cmake {
                        arguments.add("-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON")
                    }
                }
        """
    } else {
      cmake16KBAlignmentFix = ""
    }

    // TODO: Make JVM target configurable
    return """
      import org.jetbrains.kotlin.gradle.dsl.JvmTarget

      plugins {
          alias(libs.plugins.android.application)
          alias(libs.plugins.kotlin.android)
      }

      android {
          namespace = "\(packageIdentifier)"
          compileSdk = \(compileSDK)

          defaultConfig {
              applicationId = "\(packageIdentifier)"
              minSdk = \(minSDK)
              targetSdk = \(targetSDK)
              versionCode = \(versionCode)
              versionName = "\(appVersion)"

              ndk {
                  abiFilters.addAll(setOf(\(abiFilters)))
              }\(cmake16KBAlignmentFix)
          }

          externalNativeBuild {
              cmake {
                  path = file("\(cmakePath)")
              }
          }

          packaging {
              jniLibs {
      \(keepDebugSymols)
              }
          }

          buildTypes {
              release {
                  isMinifyEnabled = false
              }
          }

          compileOptions {
              sourceCompatibility = JavaVersion.VERSION_17
              targetCompatibility = JavaVersion.VERSION_17
          }
      }

      kotlin {
          compilerOptions {
              jvmTarget.set(JvmTarget.JVM_17)
          }
      }

      dependencies {
          implementation(libs.appcompat)
          implementation(libs.material)
          implementation(libs.activity)
          implementation(libs.constraintlayout)
      }

      """
  }

  private static func generateGradleSettings(forApp appName: String) -> String {
    return """
      pluginManagement {
          repositories {
              google {
                  content {
                      includeGroupByRegex("com\\\\.android.*")
                      includeGroupByRegex("com\\\\.google.*")
                      includeGroupByRegex("androidx.*")
                  }
              }
              mavenCentral()
              gradlePluginPortal()
          }
      }

      dependencyResolutionManagement {
          repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
          repositories {
              google()
              mavenCentral()
          }
      }

      rootProject.name = "\(appName)"

      """
  }

  private static func generateGradleProperties() -> String {
    return """
      # Specifies the JVM arguments used for the daemon process.
      # The setting is particularly useful for tweaking memory settings.
      org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
      # AndroidX package structure to make it clearer which packages are bundled with the
      # Android operating system, and which are packaged with your app's APK
      # https://developer.android.com/topic/libraries/support-library/androidx-rn
      android.useAndroidX=true
      # Enables namespacing of each library's R class so that its R class includes only the
      # resources declared in the library itself and none from the library's dependencies,
      # thereby reducing the size of the R class for that library
      android.nonTransitiveRClass=true

      """
  }

  private static func generateLocalProperties(androidSDK: URL) -> String {
    return "sdk.dir=\(androidSDK.path)\n"
  }

  private static func generateAndroidManifest(
    targetAPI: Int,
    themeName: String,
    appNameStringKey: String,
    projectStructure: ProjectStructure
  ) -> String {
    let iconName = projectStructure.icon.deletingPathExtension().lastPathComponent
    return """
      <?xml version="1.0" encoding="utf-8"?>
      <manifest xmlns:android="http://schemas.android.com/apk/res/android"
          xmlns:tools="http://schemas.android.com/tools">

          <application
              android:allowBackup="true"
              android:icon="@mipmap/\(iconName)"
              android:label="@string/\(appNameStringKey)"
              android:theme="@style/Theme.\(themeName)"
              tools:targetApi="\(targetAPI)">
              <activity
                  android:name=".\(projectStructure.mainActivityName)"
                  android:exported="true">
                  <intent-filter>
                      <action android:name="android.intent.action.MAIN" />
                      <category android:name="android.intent.category.LAUNCHER" />
                  </intent-filter>
              </activity>
          </application>
      </manifest>

      """
  }

  private static func generateCMakeLists(product: String) -> String {
    // We don't have any particular reason for having a minimum of 3.22 other
    // than that it's what the sample code I based my template off used. I don't
    // want to drop the minimum without testing it, but if someone needs a lower
    // version and can test it, then I have no issue with dropping it.
    return """
      cmake_minimum_required(VERSION 3.22)
      project(shim)

      add_library(app SHARED IMPORTED)
      set_target_properties(app PROPERTIES IMPORTED_LOCATION
              ${CMAKE_SOURCE_DIR}/jniLibs/${ANDROID_ABI}/lib\(product).so)

      add_library(shim SHARED shim/shim.h shim/shim.c)
      target_link_libraries(shim app)

      """
  }

  private static func generateMainActivity(packageIdentifier: String) -> String {
    return """
      package \(packageIdentifier);

      import android.graphics.Insets;
      import android.os.Bundle;
      import android.view.WindowInsets;
      import android.view.WindowMetrics;

      import androidx.appcompat.app.AppCompatActivity;

      public class MainActivity extends AppCompatActivity {
          private native void setup();

          public int getWindowWidth() {
              WindowMetrics windowMetrics = this.getWindowManager().getCurrentWindowMetrics();
              Insets insets = windowMetrics.getWindowInsets()
                      .getInsetsIgnoringVisibility(WindowInsets.Type.systemBars());
              return windowMetrics.getBounds().width() - insets.left - insets.right;
          }

          public int getWindowHeight() {
              WindowMetrics windowMetrics = this.getWindowManager().getCurrentWindowMetrics();
              Insets insets = windowMetrics.getWindowInsets()
                      .getInsetsIgnoringVisibility(WindowInsets.Type.systemBars());
              return windowMetrics.getBounds().height() - insets.top - insets.bottom;
          }

          @Override
          protected void onCreate(Bundle savedInstanceState) {
              super.onCreate(savedInstanceState);
              System.loadLibrary("shim");

              setup();
          }
      }

      """
  }

  private static func getSetupFunctionName(
    packageIdentifier: String,
    mainActivityName: String
  ) -> String {
    let namespace = packageIdentifier.replacingOccurrences(of: ".", with: "_")
    return "Java_\(namespace)_\(mainActivityName)_setup"
  }

  private static func generateShimSource(
    packageIdentifier: String,
    swiftEntryPoint: String,
    projectStructure: ProjectStructure
  ) -> String {
    let header = projectStructure.shimHeader.path(
      relativeTo: projectStructure.shimSource.deletingLastPathComponent()
    )
    let setupFunction = getSetupFunctionName(
      packageIdentifier: packageIdentifier,
      mainActivityName: projectStructure.mainActivityName
    )
    return """
      #include "\(header)"

      void \(swiftEntryPoint)(JNIEnv *env, jobject activity);

      JNIEXPORT void JNICALL
      \(setupFunction)(JNIEnv *env, jobject activity) {
          \(swiftEntryPoint)(env, activity);
      }

      """
  }

  private static func generateShimHeader(
    packageIdentifier: String,
    mainActivityName: String
  ) -> String {
    let setupFunction = getSetupFunctionName(
      packageIdentifier: packageIdentifier,
      mainActivityName: mainActivityName
    )
    return """
      #include <jni.h>

      JNIEXPORT void JNICALL
      \(setupFunction)(JNIEnv *env, jobject activity);

      """
  }

  private static func generateStringsXML(appName: String, appNameStringKey: String) -> String {
    let appName = appName.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
    return """
      <resources>
          <string name="\(appNameStringKey)">\(appName)</string>
      </resources>

      """
  }

  private static func generateGradleLibsVersions() -> String {
    // A table of AGP <-> KGP compatibility can be found at
    // https://kotlinlang.org/docs/gradle-configure-project.html#apply-the-plugin

    // TODO(stackotter): Make all of this configurable
    return """
      [versions]
      agp = "8.13.0"
      kgp = "2.3.10"
      junit = "4.13.2"
      junitVersion = "1.1.5"
      espressoCore = "3.5.1"
      appcompat = "1.6.1"
      material = "1.10.0"
      activity = "1.8.0"
      constraintlayout = "2.1.4"

      [libraries]
      junit = { group = "junit", name = "junit", version.ref = "junit" }
      ext-junit = { group = "androidx.test.ext", name = "junit", version.ref = "junitVersion" }
      espresso-core = { group = "androidx.test.espresso", name = "espresso-core", version.ref = "espressoCore" }
      appcompat = { group = "androidx.appcompat", name = "appcompat", version.ref = "appcompat" }
      material = { group = "com.google.android.material", name = "material", version.ref = "material" }
      activity = { group = "androidx.activity", name = "activity", version.ref = "activity" }
      constraintlayout = { group = "androidx.constraintlayout", name = "constraintlayout", version.ref = "constraintlayout" }

      [plugins]
      android-application = { id = "com.android.application", version.ref = "agp" }
      kotlin-android = { id = "org.jetbrains.kotlin.android", version.ref = "kgp" }

      """
  }

  private static func generateGradleWrapperProperties() -> String {
    // Make Gradle version configurable
    return """
      #Thu Apr 03 10:39:48 AEST 2025
      distributionBase=GRADLE_USER_HOME
      distributionPath=wrapper/dists
      distributionUrl=https\\://services.gradle.org/distributions/gradle-8.13-bin.zip
      zipStoreBase=GRADLE_USER_HOME
      zipStorePath=wrapper/dists

      """
  }

  private static func generateThemesXML(themeName: String, parentTheme: String) -> String {
    return """
      <resources xmlns:tools="http://schemas.android.com/tools">
          <style name="Base.Theme.\(themeName)" parent="\(parentTheme)"></style>
          <style name="Theme.\(themeName)" parent="Base.Theme.\(themeName)" />
      </resources>

      """
  }

  private static func generateNightThemesXML(themeName: String, parentTheme: String) -> String {
    return """
      <resources xmlns:tools="http://schemas.android.com/tools">
          <style name="Base.Theme.\(themeName)" parent="\(parentTheme)"></style>
      </resources>

      """
  }
}
