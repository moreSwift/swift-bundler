# macOS package

```sh
python3 Distribution/macos/build.py
```

This builds arm64 and x86_64 release binaries, combines them with `lipo`, signs
the result (ad-hoc by default), and creates:

```
Distribution/out/macos/swift-bundler-<version>-macos-universal.pkg
```

The package installs `swift-bundler` into `/usr/local/bin` and shell
completions under `/usr/local/share/`. It requires macOS 13 or newer.

Signing and notarization are opt-in:

```sh
SBUN_APP_IDENTITY="Developer ID Application: ..." \
SBUN_INSTALLER_IDENTITY="Developer ID Installer: ..." \
SBUN_NOTARY_PROFILE="notarytool-profile" \
python3 Distribution/macos/build.py
```

Uninstall:

```sh
sudo rm /usr/local/bin/swift-bundler
sudo pkgutil --forget dev.moreswift.swift-bundler
```

The zsh completion is installed to
`/usr/local/share/zsh/site-functions`; add that directory to `fpath` if your
shell does not already include it.
