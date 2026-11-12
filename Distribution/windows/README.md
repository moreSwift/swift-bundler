# Windows packages

Run from a **Developer PowerShell for Visual Studio** so that `dumpbin` is on
`PATH`:

```powershell
python Distribution\windows\build.py all
```

Produces:

```
Distribution\out\windows\swift-bundler-<version>-windows-x86_64.zip
Distribution\out\windows\swift-bundler-<version>-windows-x86_64.msi
```

The MSI installs to `C:\Program Files\Swift Bundler` and appends that directory
to the machine `PATH`. It requires elevation. The flat `.zip` is fully
self-contained.

Both packages include `sbun.cmd`, a small launcher that forwards to
`swift-bundler.exe` so that `sbun` works as an alias for `swift-bundler`.

WiX 6.0.0 is downloaded automatically from NuGet and cached under
`Distribution\out\windows\tools`. Signing is opt-in:

```powershell
$env:SBUN_WINDOWS_CERT_PATH = "C:\path\to\certificate.pfx"
$env:SBUN_WINDOWS_CERT_PASSWORD = "..."
python Distribution\windows\build.py msi --sign
```

The default timestamp server is `http://timestamp.digicert.com`; override it
with `SBUN_WINDOWS_TIMESTAMP_URL`.
