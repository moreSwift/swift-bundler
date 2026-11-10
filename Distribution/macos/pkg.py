"""Create the macOS payload and .pkg installer."""

from __future__ import annotations

import logging
import os
from pathlib import Path

from common import support

BUNDLE_IDENTIFIER = "dev.moreswift.swift-bundler"


def _generate_completions(binary: Path, payload: Path) -> None:
    locations = {
        "bash": (
            payload
            / "usr"
            / "local"
            / "share"
            / "bash-completion"
            / "completions"
            / "swift-bundler",
            0o644,
        ),
        "zsh": (
            payload
            / "usr"
            / "local"
            / "share"
            / "zsh"
            / "site-functions"
            / "_swift-bundler",
            0o644,
        ),
        "fish": (
            payload
            / "usr"
            / "local"
            / "share"
            / "fish"
            / "vendor_completions.d"
            / "swift-bundler.fish",
            0o644,
        ),
    }
    for shell, (destination, mode) in locations.items():
        result = support.run(
            [str(binary), "--generate-completion-script", shell],
            capture=True,
        )
        support.ensure_directory(destination.parent)
        destination.write_text(result.stdout or "", encoding="utf-8")
        os.chmod(destination, mode)


def _create_payload(universal: Path, output_dir: Path, version: str) -> Path:
    payload = output_dir / f"payload-{version}"
    support.remove_path(payload)
    support.ensure_directory(payload)

    binary = payload / "usr" / "local" / "bin" / "swift-bundler"
    support.copy_file(universal, binary, mode=0o755)

    docs = payload / "usr" / "local" / "share" / "doc" / "swift-bundler"
    support.ensure_directory(docs)
    support.copy_file(support.REPO_ROOT / "LICENSE", docs / "LICENSE", mode=0o644)
    support.copy_file(support.REPO_ROOT / "README.md", docs / "README.md", mode=0o644)

    _generate_completions(binary, payload)
    return payload


def _write_distribution(output_dir: Path, version: str, payload: Path) -> Path:
    template = (
        support.DISTRIBUTION_ROOT / "macos" / "distribution.xml.in"
    ).read_text(encoding="utf-8")
    contents = support.render_template(
        template,
        {
            "VERSION": version,
            "INSTALL_KBYTES": str(support.installed_size_kb(payload)),
        },
        source_name="macos/distribution.xml.in",
    )
    destination = output_dir / "distribution.xml"
    destination.write_text(contents, encoding="utf-8")
    return destination


def _finalize_installer(unsigned: Path, installer: Path) -> None:
    identity = os.environ.get("SBUN_INSTALLER_IDENTITY")
    support.remove_path(installer)
    if not identity:
        logging.warning(
            "SBUN_INSTALLER_IDENTITY is not set; the .pkg will be unsigned"
        )
        unsigned.rename(installer)
        return

    support.run(
        [
            "productsign",
            "--sign",
            identity,
            str(unsigned),
            str(installer),
        ]
    )
    support.remove_path(unsigned)


def _notarize(installer: Path) -> None:
    profile = os.environ.get("SBUN_NOTARY_PROFILE")
    identity = os.environ.get("SBUN_INSTALLER_IDENTITY")
    if not profile or not identity:
        logging.info(
            "Signing/notarization credentials are not fully configured; "
            "skipping notarization"
        )
        return

    support.run(
        [
            "xcrun",
            "notarytool",
            "submit",
            str(installer),
            "--keychain-profile",
            profile,
            "--wait",
        ]
    )
    support.run(["xcrun", "stapler", "staple", str(installer)])
    support.run(["spctl", "--assess", "--type", "install", str(installer)])


def build_pkg(universal: Path, output_dir: Path, version: str) -> Path:
    support.require_command("pkgbuild")
    support.require_command("productbuild")

    payload = _create_payload(universal, output_dir, version)

    component = output_dir / "component.pkg"
    support.remove_path(component)
    support.run(
        [
            "pkgbuild",
            "--root",
            str(payload),
            "--identifier",
            BUNDLE_IDENTIFIER,
            "--version",
            version,
            "--install-location",
            "/",
            "--ownership",
            "recommended",
            str(component),
        ]
    )

    distribution = _write_distribution(output_dir, version, payload)
    installer = output_dir / f"swift-bundler-{version}-macos-universal.pkg"
    unsigned = output_dir / "swift-bundler-unsigned.pkg"
    support.remove_path(unsigned)
    support.run(
        [
            "productbuild",
            "--distribution",
            str(distribution),
            "--package-path",
            str(output_dir),
            "--resources",
            str(support.DISTRIBUTION_ROOT / "macos" / "resources"),
            str(unsigned),
        ]
    )

    _finalize_installer(unsigned, installer)
    _notarize(installer)
    support.write_checksum(installer)
    logging.info("Created %s", installer)
    return installer
