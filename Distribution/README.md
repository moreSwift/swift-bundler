# Swift Bundler distribution

This directory builds portable Swift Bundler installers and loose distributions:

| Platform | Installer | Loose distribution |
|----------|-----------|--------------------|
| macOS | `.pkg` | — |
| Linux | `.deb`, `.rpm` | `.tar.gz` |
| Windows | `.msi` (WiX 6) | `.zip` |

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
Linux and Windows packages are built natively; requesting a different target
architecture is rejected rather than silently producing a mislabelled package.

## Prerequisites

Common:

- Python 3.9 or newer.
- A Swift 6.3 or newer toolchain. If multiple toolchains are installed, set
  `SBUN_TOOLCHAIN_BIN` to a `PATH`-style list of directories to prepend when
  locating `swift`/`swiftc`.
- The repository's SwiftPM dependencies (SwiftPM fetches them on first build).

Linux:

- `patchelf` for runpath patching.
- `dpkg-deb` and `dpkg-shlibdeps` for `.deb`.
- `rpmbuild` for `.rpm` (the `rpm` package on Debian/Ubuntu, `rpm-build` on
  Fedora).
- Build on the oldest distribution the Swift toolchain supports to keep the
  glibc floor low. Ubuntu 22.04 is a good default for `.deb` and the loose
  tarball.

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

- **Linux:** Swift runtime libraries are copied into `/usr/lib/swift-bundler`
  and found through a `$ORIGIN` runpath. System ABI libraries (libc, libm,
  libpthread, libdl, librt, libgcc_s, libstdc++, the dynamic loader) are not
  bundled and are declared as package dependencies.
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

## Tests

The pure parsing/template logic is covered by standard-library `unittest`
tests:

```sh
python3 -m unittest discover -s Distribution/tests -t Distribution
python3 -m compileall -q Distribution
```

## Layout

```
Distribution/
  build.py                  # optional cross-platform dispatcher
  common/support.py         # version, process, template, archive helpers
  macos/                    # universal build + .pkg
  linux/                    # staging + .deb/.rpm/.tar.gz
  windows/                  # staging + .zip/.msi
  tests/                    # unittest suite and fixtures
```
