import Testing
import Foundation
import XMLCoder

@testable import SwiftBundler

@Suite
struct AppxManifestTests {
  @Test func emptyPackageFieldsShouldNotBeEncoded() throws {
    let manifest = AppxManifest.Package(
      identity: AppxManifest.Identity(
        name: "com.example.app",
        publisher: "CN=Example",
        version: "1.0.0.0",
        processorArchitecture: "x64"
      ),
      properties: AppxManifest.Properties(
        displayName: "Example App",
        publisherDisplayName: "Example Publisher",
        logo: "Assets\\Logo.png"
      ),
      resources: [],
      dependencies: [],
      capabilities: [],
      applications: []
    )
    let xmlString = String(
      data: try AppxManifest.encodeManifest(
        manifest,
        disablingRootAttributesForTesting: true
      ),
      encoding: .utf8
    )

    #expect(xmlString == """
    <?xml version="1.0" encoding="utf-8"?>
    <Package>
        <Identity Name="com.example.app" Publisher="CN=Example" Version="1.0.0.0" ProcessorArchitecture="x64" />
        <Properties>
            <DisplayName>Example App</DisplayName>
            <PublisherDisplayName>Example Publisher</PublisherDisplayName>
            <Logo>Assets\\Logo.png</Logo>
        </Properties>
    </Package>
    """)
  }

  @Test func missingPackageFieldsShouldBeDecodedAsEmpty() throws {
    let xmlString = """
    <?xml version="1.0" encoding="utf-8"?>
    <Package>
        <Identity Name="com.example.app" Publisher="CN=Example" Version="1.0.0.0" ProcessorArchitecture="x64" />
        <Properties>
            <DisplayName>Example App</DisplayName>
            <PublisherDisplayName>Example Publisher</PublisherDisplayName>
            <Logo>Assets\\Logo.png</Logo>
        </Properties>
    </Package>
    """

    let manifest = try XMLDecoder().decode(
      AppxManifest.Package.self,
      from: Data(xmlString.utf8)
    )
    #expect(manifest == AppxManifest.Package(
      identity: AppxManifest.Identity(
        name: "com.example.app",
        publisher: "CN=Example",
        version: "1.0.0.0",
        processorArchitecture: "x64"
      ),
      properties: AppxManifest.Properties(
        displayName: "Example App",
        publisherDisplayName: "Example Publisher",
        logo: "Assets\\Logo.png"
      ),
      resources: [],
      dependencies: [],
      capabilities: [],
      applications: []
    ))
  }

  @Test func emptyApplicationDependenciesShouldNotBeEncoded() throws {
    let manifest = AppxManifest.Package(
      identity: AppxManifest.Identity(
        name: "com.example.app",
        publisher: "CN=Example",
        version: "1.0.0.0",
        processorArchitecture: "x64"
      ),
      properties: AppxManifest.Properties(
        displayName: "Example App",
        publisherDisplayName: "Example Publisher",
        logo: "Assets\\Logo.png"
      ),
      resources: [],
      dependencies: [],
      capabilities: [],
      applications: [
        AppxManifest.Application(
          id: "com.example.app",
          executable: "ExampleApp.exe",
          entryPoint: "Windows.FullTrustApplication",
          uapVisualElements: nil,
          extensions: []
        )
      ]
    )
    let xmlString = String(
      data: try AppxManifest.encodeManifest(
        manifest,
        disablingRootAttributesForTesting: true
      ),
      encoding: .utf8
    )
    #expect(xmlString == """
    <?xml version="1.0" encoding="utf-8"?>
    <Package>
        <Identity Name="com.example.app" Publisher="CN=Example" Version="1.0.0.0" ProcessorArchitecture="x64" />
        <Properties>
            <DisplayName>Example App</DisplayName>
            <PublisherDisplayName>Example Publisher</PublisherDisplayName>
            <Logo>Assets\\Logo.png</Logo>
        </Properties>
        <Applications>
            <Application Id="com.example.app" Executable="ExampleApp.exe" EntryPoint="Windows.FullTrustApplication" />
        </Applications>
    </Package>
    """)
  }

  @Test func missingApplicationDependenciesShouldBeDecodedAsEmpty() throws {
    let xmlString = """
    <?xml version="1.0" encoding="utf-8"?>
    <Package>
        <Identity Name="com.example.app" Publisher="CN=Example" Version="1.0.0.0" ProcessorArchitecture="x64" />
        <Properties>
            <DisplayName>Example App</DisplayName>
            <PublisherDisplayName>Example Publisher</PublisherDisplayName>
            <Logo>Assets\\Logo.png</Logo>
        </Properties>
        <Applications>
            <Application Id="com.example.app" Executable="ExampleApp.exe" EntryPoint="Windows.FullTrustApplication" />
        </Applications>
    </Package>
    """

    let manifest = try XMLDecoder().decode(
      AppxManifest.Package.self,
      from: Data(xmlString.utf8)
    )
    #expect(manifest == AppxManifest.Package(
      identity: AppxManifest.Identity(
        name: "com.example.app",
        publisher: "CN=Example",
        version: "1.0.0.0",
        processorArchitecture: "x64"
      ),
      properties: AppxManifest.Properties(
        displayName: "Example App",
        publisherDisplayName: "Example Publisher",
        logo: "Assets\\Logo.png"
      ),
      resources: [],
      dependencies: [],
      capabilities: [],
      applications: [
        AppxManifest.Application(
          id: "com.example.app",
          executable: "ExampleApp.exe",
          entryPoint: "Windows.FullTrustApplication",
          uapVisualElements: nil,
          extensions: []
        )
      ]
    ))
  }

  @Test func manifestStressTestShouldEncodeAndDecodeSuccessfully() throws {
    let stressTestManifest = AppxManifest.Package(
      identity: AppxManifest.Identity(
        name: "com.example.app",
        publisher: "CN=Example",
        version: "1.0.0.0",
        processorArchitecture: "x64"
      ),
      properties: AppxManifest.Properties(
        displayName: "Example App",
        publisherDisplayName: "Example Publisher",
        logo: "Assets\\Logo.png"
      ),
      resources: [
        AppxManifest.Resource(language: "en-US"),
        AppxManifest.Resource(language: "fr-FR")
      ],
      dependencies: [
        .targetDeviceFamily(
          AppxManifest.TargetDeviceFamily(
            name: "Windows.Desktop",
            minimumVersion: "10.0.18362.0",
            maximumVersionTested: "10.0.22631.0"
          )
        ),
        .packageDependency(
          AppxManifest.PackageDependency(
            name: "Microsoft.WindowsAppRuntime.1.5",
            publisher: "CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US",
            minimumVersion: "5000.617.317.0"
          )
        ),
        .packageDependency(
          AppxManifest.PackageDependency(
            name: "Microsoft.VCLibs.140.00.UWPDesktop",
            publisher: "CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US",
            minimumVersion: "14.0.33728.0"
          )
        )
      ],
      capabilities: [
        .capability(AppxManifest.Capability(name: "internetClient")),
        .rescapCapability(AppxManifest.RescapCapability(name: "runFullTrust")),
        .deviceCapability(AppxManifest.DeviceCapability(name: "microphone")),
        .deviceCapability(AppxManifest.DeviceCapability(name: "bluetooth")),
        .deviceCapability(AppxManifest.DeviceCapability(name: "location")),
        .deviceCapability(AppxManifest.DeviceCapability(name: "webcam")),
      ],
      applications: [
        AppxManifest.Application(
          id: "com.example.app",
          executable: "ExampleApp.exe",
          entryPoint: "Windows.FullTrustApplication",
          uapVisualElements: AppxManifest.UAPVisualElements(
            displayName: "Example App",
            description: "An example app for testing.",
            backgroundColor: "#FFFFFF",
            square150x150Logo: "Assets\\Square150x150Logo.png",
            square44x44Logo: "Assets\\Square44x44Logo.png"
          ),
          extensions: [
            .desktopExtension(
              .fullTrustProcess(
                AppxManifest.ApplicationDesktopFullTrustProcess(executable: "ExampleApp.exe")
              )
            ),
            .uap3Extension(
              .uap3Protocol(
                AppxManifest.ApplicationUAP3Protocol(
                  name: "example",
                  displayName: "Example Protocol",
                  logo: "Assets\\ProtocolLogo.png"
                )
              )
            )
          ]
        ),
        AppxManifest.Application(
          id: "com.example.app.helper",
          executable: "HelperApp.exe",
          entryPoint: "Windows.FullTrustApplication",
          uapVisualElements: nil,
          extensions: []
        )
      ]
    )
    let stressTestXML = """
    <?xml version="1.0" encoding="utf-8"?>
    <Package>
        <Identity Name="com.example.app" Publisher="CN=Example" Version="1.0.0.0" ProcessorArchitecture="x64" />
        <Properties>
            <DisplayName>Example App</DisplayName>
            <PublisherDisplayName>Example Publisher</PublisherDisplayName>
            <Logo>Assets\\Logo.png</Logo>
        </Properties>
        <Resources>
            <Resource Language="en-US" />
            <Resource Language="fr-FR" />
        </Resources>
        <Dependencies>
            <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.18362.0" MaxVersionTested="10.0.22631.0" />
            <PackageDependency Name="Microsoft.WindowsAppRuntime.1.5" Publisher="CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US" MinVersion="5000.617.317.0" />
            <PackageDependency Name="Microsoft.VCLibs.140.00.UWPDesktop" Publisher="CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US" MinVersion="14.0.33728.0" />
        </Dependencies>
        <Capabilities>
            <Capability Name="internetClient" />
            <rescap:Capability Name="runFullTrust" />
            <DeviceCapability Name="microphone" />
            <DeviceCapability Name="bluetooth" />
            <DeviceCapability Name="location" />
            <DeviceCapability Name="webcam" />
        </Capabilities>
        <Applications>
            <Application Id="com.example.app" Executable="ExampleApp.exe" EntryPoint="Windows.FullTrustApplication">
                <uap:VisualElements DisplayName="Example App" Description="An example app for testing." BackgroundColor="#FFFFFF" Square150x150Logo="Assets\\Square150x150Logo.png" Square44x44Logo="Assets\\Square44x44Logo.png" />
                <Extensions>
                    <desktop:Extension Category="windows.fullTrustProcess" Executable="ExampleApp.exe" />
                    <uap3:Extension Category="windows.protocol">
                        <uap3:Protocol Name="example">
                            <uap:DisplayName>Example Protocol</uap:DisplayName>
                            <uap:Logo>Assets\\ProtocolLogo.png</uap:Logo>
                        </uap3:Protocol>
                    </uap3:Extension>
                </Extensions>
            </Application>
            <Application Id="com.example.app.helper" Executable="HelperApp.exe" EntryPoint="Windows.FullTrustApplication" />
        </Applications>
    </Package>
    """

    let encodedXMLString = String(
      data: try AppxManifest.encodeManifest(
        stressTestManifest,
        disablingRootAttributesForTesting: true
      ),
      encoding: .utf8
    )
    #expect(encodedXMLString == stressTestXML)

    let decodedManifest = try XMLDecoder().decode(
      AppxManifest.Package.self,
      from: Data(stressTestXML.utf8)
    )
    #expect(decodedManifest == stressTestManifest)
  }
}
