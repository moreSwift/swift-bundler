"""Build and verify a WiX MSI for Swift Bundler."""

from __future__ import annotations

import logging
import os
import shutil
import tempfile
import urllib.request
import zipfile
from pathlib import Path
from typing import List, Optional

from common import support
from windows.staging import Stage

WIX_VERSION = "6.0.0"
WIX_DOWNLOAD_URL = "https://www.nuget.org/api/v2/package/wix/6.0.0"
UI_EXTENSION = f"WixToolset.UI.wixext/{WIX_VERSION}"
DEFAULT_TIMESTAMP_URL = "http://timestamp.digicert.com"


def _find_wix_in_extracted_package(root: Path) -> Path:
    preferred = root / "tools" / "net8.0" / "any" / "wix.exe"
    if preferred.is_file():
        return preferred

    candidates = sorted(
        (root / "tools").glob("net*/any/wix.exe"),
        reverse=True,
    )
    if candidates:
        return candidates[0]

    matches = sorted(root.rglob("wix.exe"))
    if matches:
        return matches[0]

    raise support.PackagingError(
        f"Failed to locate wix.exe in the downloaded WiX package at {root}"
    )


def get_wix_cli(output_dir: Path) -> Path:
    tools_root = support.ensure_directory(output_dir / "tools")
    install_directory = tools_root / f"wix-{WIX_VERSION}"
    wix = install_directory / "wix.exe"
    if wix.is_file():
        return wix

    logging.info("Downloading WiX %s", WIX_VERSION)
    with tempfile.TemporaryDirectory(
        prefix="swift-bundler-wix-", dir=str(tools_root)
    ) as temporary:
        work = Path(temporary)
        archive = work / "wix.nupkg"
        with urllib.request.urlopen(WIX_DOWNLOAD_URL, timeout=120) as response:
            with archive.open("wb") as file:
                shutil.copyfileobj(response, file)

        extracted = work / "extracted"
        extracted.mkdir()
        with zipfile.ZipFile(archive) as zip_file:
            zip_file.extractall(extracted)

        wix_in_package = _find_wix_in_extracted_package(extracted)
        support.remove_path(install_directory)
        shutil.copytree(wix_in_package.parent, install_directory)

    if not wix.is_file():
        raise support.PackagingError(f"WiX installation is missing {wix}")
    return wix


def ensure_ui_extension(wix: Path, windows_directory: Path) -> None:
    logging.info("Ensuring WiX extension %s", UI_EXTENSION)
    result = support.run(
        [str(wix), "extension", "add", UI_EXTENSION],
        cwd=windows_directory,
        capture=True,
        check=False,
    )
    output = ((result.stdout or "") + (result.stderr or "")).lower()
    if result.returncode != 0 and "already" not in output:
        raise support.PackagingError(
            f"Failed to install WiX extension {UI_EXTENSION}:\n"
            f"{(result.stdout or '') + (result.stderr or '')}"
        )


def sign_file(path: Path) -> None:
    certificate = os.environ.get("SBUN_WINDOWS_CERT_PATH")
    password = os.environ.get("SBUN_WINDOWS_CERT_PASSWORD")
    if not certificate or not password:
        raise support.PackagingError(
            "Signing was requested but SBUN_WINDOWS_CERT_PATH and "
            "SBUN_WINDOWS_CERT_PASSWORD are not both set."
        )

    signtool = shutil.which("signtool")
    if signtool is None:
        raise support.PackagingError(
            "Required command not found: signtool. Install the Windows SDK."
        )

    timestamp = os.environ.get(
        "SBUN_WINDOWS_TIMESTAMP_URL", DEFAULT_TIMESTAMP_URL
    )
    support.run(
        [
            signtool,
            "sign",
            "/fd",
            "SHA256",
            "/f",
            certificate,
            "/p",
            password,
            "/tr",
            timestamp,
            "/td",
            "SHA256",
            str(path),
        ]
    )


def _verify_msi(msi: Path, output_dir: Path) -> None:
    msiexec = shutil.which("msiexec")
    if msiexec is None:
        system_root = os.environ.get("SystemRoot")
        if system_root:
            candidate = Path(system_root) / "System32" / "msiexec.exe"
            if candidate.is_file():
                msiexec = str(candidate)
    if msiexec is None:
        raise support.PackagingError(
            "msiexec was not found; cannot verify the MSI"
        )

    with tempfile.TemporaryDirectory(
        prefix="swift-bundler-msi-verify-", dir=str(output_dir)
    ) as temporary:
        verify_dir = Path(temporary)
        result = support.run(
            [
                msiexec,
                "/a",
                str(msi),
                "/qn",
                f"TARGETDIR={verify_dir}",
            ],
            capture=True,
            check=False,
        )
        if result.returncode not in (0, 3010):
            raise support.PackagingError(
                "MSI administrative extraction failed with exit code "
                f"{result.returncode}:\n"
                f"{(result.stdout or '') + (result.stderr or '')}"
            )

        executables = list(verify_dir.rglob("swift-bundler.exe"))
        if not executables:
            raise support.PackagingError(
                "MSI administrative extraction did not contain swift-bundler.exe"
            )
        logging.info("MSI verification extracted %s", executables[0])


def build_msi(
    stage: Stage,
    output_dir: Path,
    *,
    dry_run: bool = False,
) -> Path:
    output = output_dir / (
        f"swift-bundler-{stage.version}-windows-{stage.arch}.msi"
    )
    if dry_run:
        logging.info("[dry-run] would build %s", output)
        return output

    windows_directory = support.DISTRIBUTION_ROOT / "windows"
    wix = get_wix_cli(output_dir)
    ensure_ui_extension(wix, windows_directory)

    support.run(
        [
            str(wix),
            "build",
            "-b",
            str(stage.root),
            "-o",
            str(output),
            "-arch",
            support.wix_arch(stage.arch),
            "-d",
            f"Version={stage.version}",
            "-ext",
            "WixToolset.UI.wixext",
            str(windows_directory / "swift-bundler.wxs"),
        ],
        cwd=windows_directory,
    )

    _verify_msi(output, output_dir)
    support.remove_path(output.with_suffix(".wixpdb"))
    logging.info("Created %s", output)
    return output


def print_plan(stage: Stage, output_dir: Path) -> None:
    logging.info("Would download WiX %s if needed", WIX_VERSION)
    logging.info(
        "Would run wix build for %s (%s) in %s",
        stage.version,
        stage.arch,
        output_dir,
    )
