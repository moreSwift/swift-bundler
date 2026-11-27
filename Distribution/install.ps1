#!/usr/bin/env pwsh
<#
.SYNOPSIS
Installs Swift Bundler from the artifacts attached to a GitHub release.

.DESCRIPTION
By default this installs the .msi, which installs for all users and needs
administrator privileges. When the script isn't already elevated it asks for
them with a UAC prompt. Use -Prefix to extract the loose .zip into a directory
instead, which does not require elevation.

.PARAMETER Version
Version to install. Defaults to the latest release.

.PARAMETER Prefix
Install the loose .zip into this directory instead of running the .msi.

.PARAMETER AddToPath
Add the prefix to the user PATH (only used together with -Prefix).

.PARAMETER DryRun
Print what would be installed without doing it.
#>
[CmdletBinding()]
param(
  [string]$Version = $env:SWIFT_BUNDLER_VERSION,
  [string]$Prefix = $env:SWIFT_BUNDLER_PREFIX,
  [switch]$AddToPath,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$Repository = if ($env:SWIFT_BUNDLER_REPOSITORY) {
  $env:SWIFT_BUNDLER_REPOSITORY
} else {
  'moreSwift/swift-bundler'
}
$ApiUrl = if ($env:SWIFT_BUNDLER_API_URL) {
  $env:SWIFT_BUNDLER_API_URL
} else {
  "https://api.github.com/repos/$Repository/releases/latest"
}
$DownloadUrl = if ($env:SWIFT_BUNDLER_DOWNLOAD_URL) {
  $env:SWIFT_BUNDLER_DOWNLOAD_URL
} else {
  "https://github.com/$Repository/releases/download"
}

$Architecture = switch ($env:PROCESSOR_ARCHITECTURE) {
  'AMD64' { 'x86_64' }
  'ARM64' { 'arm64' }
  default { throw "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE" }
}

if ([string]::IsNullOrWhiteSpace($Version)) {
  Write-Host "Looking up the latest release of $Repository"
  $Latest = Invoke-RestMethod -Uri $ApiUrl -Headers @{
    'User-Agent' = 'swift-bundler-install'
  }
  $Tag = $Latest.tag_name
  if (-not $Tag) {
    throw "Could not determine the latest release from $ApiUrl"
  }
} else {
  $Tag = if ($Version.StartsWith('v')) { $Version } else { "v$Version" }
}
$VersionNumber = $Tag -replace '^v', ''

if ($Prefix) {
  $Mode = 'zip'
  $Asset = "swift-bundler-$VersionNumber-windows-$Architecture.zip"
  $Description = "loose .zip in $Prefix"
} else {
  $Mode = 'msi'
  $Asset = "swift-bundler-$VersionNumber-windows-$Architecture.msi"
  $Description = '.msi installer (requests administrator privileges)'
}
$Url = "$DownloadUrl/$Tag/$Asset"

if ($DryRun) {
  Write-Host "Swift Bundler $VersionNumber"
  Write-Host "  asset:  $Asset"
  Write-Host "  url:    $Url"
  Write-Host "  method: $Description"
  return
}

if ($Prefix) {
  $Prefix = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
    $Prefix
  )
}

$Temp = Join-Path ([IO.Path]::GetTempPath()) (
  'swift-bundler-' + [Guid]::NewGuid().ToString('N')
)
New-Item -ItemType Directory -Path $Temp | Out-Null

try {
  $File = Join-Path $Temp $Asset
  Write-Host "Downloading $Url"
  try {
    Invoke-WebRequest -Uri $Url -OutFile $File -UseBasicParsing
  } catch {
    throw "Failed to download $Url (does release $Tag publish $Asset?)"
  }

  try {
    Invoke-WebRequest -Uri "$Url.sha256" -OutFile "$File.sha256" `
      -UseBasicParsing -ErrorAction Stop
  } catch {
    Remove-Item "$File.sha256" -ErrorAction SilentlyContinue
  }
  if (Test-Path "$File.sha256") {
    $Expected = (Get-Content "$File.sha256").Split(' ')[0]
    $Actual = (Get-FileHash -Algorithm SHA256 $File).Hash
    if ($Expected.ToLowerInvariant() -ne $Actual.ToLowerInvariant()) {
      throw "Checksum mismatch for $Asset"
    }
  }

  if ($Mode -eq 'msi') {
    # Windows Installer installs the .msi for all users (Program Files), so the
    # install itself has to be elevated. Start msiexec with the `runas` verb so
    # that an unprivileged session gets a UAC prompt.
    Write-Host 'Requesting administrator privileges for the .msi installer'
    try {
      $Process = Start-Process -FilePath 'msiexec.exe' -Verb RunAs `
        -ArgumentList @('/i', "`"$File`"", '/qn', '/norestart') `
        -Wait -PassThru -ErrorAction Stop
    } catch {
      throw (
        'The .msi installer installs for all users and needs administrator ' +
        "privileges, but elevation failed: $($_.Exception.Message)`n" +
        'Re-run from an administrator terminal, or install without elevation ' +
        'by passing -Prefix <dir> (or setting SWIFT_BUNDLER_PREFIX) to use ' +
        'the loose .zip instead.'
      )
    }

    # 3010 means a reboot is required but the install succeeded.
    if ($Process.ExitCode -ne 0 -and $Process.ExitCode -ne 3010) {
      throw "msiexec failed with exit code $($Process.ExitCode)"
    }

    $Executable = Join-Path $env:ProgramFiles 'Swift Bundler\swift-bundler.exe'
    & $Executable --version
    Write-Host "Installed Swift Bundler $VersionNumber"
  } else {
    $Extract = Join-Path $Temp 'extracted'
    Expand-Archive -Path $File -DestinationPath $Extract -Force
    $Root = Get-ChildItem -Path $Extract -Directory | Select-Object -First 1
    if (-not $Root) {
      throw "Unexpected archive layout in $Asset"
    }

    New-Item -ItemType Directory -Force -Path $Prefix | Out-Null
    Copy-Item -Path (Join-Path $Root.FullName '*') -Destination $Prefix `
      -Recurse -Force

    if ($AddToPath) {
      $UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
      $Entries = @()
      if ($UserPath) {
        $Entries = $UserPath -split ';'
      }
      if ($Entries -notcontains $Prefix) {
        $NewPath = (@($Entries | Where-Object { $_ }) + $Prefix) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $NewPath, 'User')
        Write-Host "Added $Prefix to the user PATH"
      }
    }

    & (Join-Path $Prefix 'swift-bundler.exe') --version
    Write-Host "Installed Swift Bundler $VersionNumber to $Prefix"
  }
} finally {
  Remove-Item -Recurse -Force $Temp -ErrorAction SilentlyContinue
}
