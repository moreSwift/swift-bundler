# Swift Bundler distribution

This directory builds portable Swift Bundler installers and loose distributions:

| Platform | Installer | Loose distribution |
|----------|-----------|--------------------|
| macOS | `.pkg` | universal CLI binary |
| Linux | `.deb`, `.rpm` | `.tar.gz` |
| Windows | `.msi` (WiX 6) | `.zip` |

Every package installs a short `sbun` alias alongside `swift-bundler`:
a symlink on Linux/macOS and a `sbun.cmd` launcher on Windows. Linux and
macOS packages also install shell completions for both command names.

All drivers are Python 3.9+ scripts using only the standard library. They invoke
the platform's native packaging tools (`wix`, `dpkg-deb`, `rpmbuild`,
`pkgbuild`, `productbuild`) rather than reimplementing their formats.

Artifacts are written to `Distribution/out/<platform>/` by default.

## Quick start

```sh
# macOS
python3 Distribution/macos/build.py

# Linux (loose + deb + rpm)
python3 Distribution/linux/build.py all
python3 Distribution/linux/build.py deb --arch arm64

# Windows (from a Developer PowerShell for VS)
python Distribution\windows\build.py all
python Distribution\windows\build.py msi --arch x86_64
```

A dispatcher is also available:

```sh
python3 Distribution/build.py linux all
python3 Distribution/build.py macos
python Distribution\build.py windows msi
```

Run any script with `--help` for the full option list. `--dry-run` prints the
commands that would be executed, and `--skip-build` reuses an existing build.
Windows packages are built natively; requesting a different target
architecture is rejected rather than silently producing a mislabelled package.
Linux packages are also built natively, but can be cross-compiled on macOS
(`--arch` defaults to `x86_64` there); see `linux/README.md`.

## Prerequisites

Common:

- Python 3.9 or newer.
- A Swift 6.3 or newer toolchain. If multiple toolchains are installed, set
  `SBUN_TOOLCHAIN_BIN` to a `PATH`-style list of directories to prepend when
  locating `swift`/`swiftc`.
- The repository's SwiftPM dependencies (SwiftPM fetches them on first build).

Linux:

- `dpkg-deb` for `.deb`.
- `rpmbuild` for `.rpm` (the `rpm` package on Debian/Ubuntu, `rpm-build` on
  Fedora).
- Network access the first time the Static Linux SDK is downloaded.
- The script automatically downloads and installs the matching Static Linux
  SDK when it is not already present. Set `SBUN_STATIC_LINUX_SDK` to an
  installed SDK selector to use an existing installation and skip the
  download.

Cross-compiling Linux on macOS additionally needs an open-source Swift
toolchain of the same version as the Static Linux SDK (it supplies the Linux
linker and readable SDK modules), plus `dpkg-deb` and `rpmbuild` from Homebrew
(`brew install dpkg rpm`). See `linux/README.md` for details.

Windows:

- A **Developer PowerShell for Visual Studio** (or any environment where
  `dumpbin` is on `PATH`).
- WiX is downloaded automatically (WiX 6.0.0 from NuGet), matching
  `WiXTool.ensureWiXCLI` in Swift Bundler itself.

macOS:

- Xcode Command Line Tools (provides `swift`, `lipo`, `codesign`, `pkgbuild`,
  and `productbuild`).
- The `.pkg` targets macOS 13 or newer.

## Versioning

The version is read from `_version = Version(x, y, z)` in
`Sources/SwiftBundler/SwiftBundler.swift`. Override it with `--version` or
`SBUN_VERSION`. Packaging requires a numeric `MAJOR.MINOR.PATCH` version because
MSI cannot represent pre-release metadata.

Package revisions can be set with `--deb-revision` / `--rpm-release`, or
`SBUN_DEB_REVISION` / `SBUN_RPM_RELEASE`.

## Runtime libraries

- **Linux:** Swift Bundler is built with the official Static Swift Linux SDK,
  producing a fully statically linked executable with no runtime library
  dependencies. The script downloads and installs the matching SDK if needed.
- **Windows:** Swift and MSVC runtime DLLs are placed next to
  `swift-bundler.exe`. Windows finds them automatically.
- **macOS:** the Swift runtime is provided by macOS; the package contains a
  single universal binary.

## Signing

### macOS

```sh
SBUN_APP_IDENTITY="Developer ID Application: Example (TEAMID)" \
SBUN_INSTALLER_IDENTITY="Developer ID Installer: Example (TEAMID)" \
SBUN_NOTARY_PROFILE="notarytool-profile" \
python3 Distribution/macos/build.py
```

Without these variables the binary is ad-hoc signed and the `.pkg` is unsigned;
Gatekeeper will warn when the package is opened.

Uninstall:

```sh
sudo rm /usr/local/bin/swift-bundler
sudo pkgutil --forget dev.moreswift.swift-bundler
```

### Windows

```powershell
$env:SBUN_WINDOWS_CERT_PATH = "C:\path\to\certificate.pfx"
$env:SBUN_WINDOWS_CERT_PASSWORD = "..."
python Distribution\windows\build.py msi --sign
```

The timestamp server defaults to `http://timestamp.digicert.com`; override it
with `SBUN_WINDOWS_TIMESTAMP_URL`.

### In GitHub Actions

`.github/workflows/distribution.yml` reads signing config from environment
secrets and variables (see [Credential storage](#credential-storage) below).
When given an empty environment, the workflow produces an unsigned installer.

| Secret | Value |
|--------|-------|
| `MACOS_CERTIFICATES_P12` | base64 of a `.p12` containing both Developer ID identities and their private keys |
| `MACOS_CERTIFICATES_PASSWORD` | the password of the `.p12` export |
| `MACOS_ASC_KEY_P8` | base64 of an App Store Connect API key (`.p8`) for notarization |

| Variable | Value |
|----------|-------|
| `MACOS_APP_IDENTITY` | `Developer ID Application: Name (TEAMID)` |
| `MACOS_INSTALLER_IDENTITY` | `Developer ID Installer: Name (TEAMID)` |
| `MACOS_NOTARY_PROFILE` | any profile name, e.g. `swift-bundler`; setting it enables notarization |
| `MACOS_ASC_KEY_ID`, `MACOS_ASC_ISSUER_ID` | App Store Connect key ID and issuer ID (leave the issuer empty for individual keys) |

The workflow imports the certificates into a temporary keychain, stores the
notarization credentials under `MACOS_NOTARY_PROFILE`, and the build then signs,
notarizes, staples, and Gatekeeper-assesses the `.pkg`.

#### Tips

You can discover the required `MACOS_INSTALLER_IDENTITY` and `MACOS_APP_IDENTITY`
values after installing the relevant certificates locally: `security find-identity -v`.

Encode your p12 (exported from Xcode) using the following command (which copies
the result to your clipboard):

```sh
base64 -i certificates.p12 | pbcopy
```

### Credential storage

The workflow reads the macOS signing secrets and variables from an environment named
`distribution`. This allows us to require that a maintainer approves each run of the
workflow, and that the workflow can only be dispatched on against the `main` branch.
Both of those measures protect us against our signing credentials being leaked.

Repository secrets are readable by any workflow run that a write-access
collaborator can push to or dispatch from a branch, and a fork pull request
runs with *no* secrets at all. The environment's branch rule and approval gate
turn "has write access" into "cannot extract the certificates without another
maintainer approving".

## Tests

The pure parsing/template logic is covered by unit tests:

```sh
python3 Distribution/test.py            # add -v for each test name
python3 -m compileall -q Distribution
```

## Layout

```
Distribution/
  build.py                  # optional cross-platform dispatcher
  test.py                   # discovers and runs the unittest suite
  common/support.py         # version, process, template, archive helpers
  macos/                    # universal build + .pkg
  linux/                    # staging + .deb/.rpm/.tar.gz
  windows/                  # staging + .zip/.msi
  tests/                    # unittest suite and fixtures
```
