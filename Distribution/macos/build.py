#!/usr/bin/env python3
"""Build Swift Bundler's macOS universal binary and .pkg installer."""

from __future__ import annotations

import argparse
import logging
import os
import platform
import sys
from pathlib import Path

DISTRIBUTION_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(DISTRIBUTION_ROOT))

from common import support  # noqa: E402
from macos import pkg  # noqa: E402

ARCHITECTURES = ("arm64", "x86_64")


def build_architecture(
    arch: str,
    work_directory: Path,
    configuration: str,
    *,
    skip_build: bool,
) -> Path:
    destination = work_directory / f"swift-bundler-{arch}"
    if skip_build and destination.is_file():
        return destination

    env = support.build_environment({"SBUN_NO_SCHEMA_GEN": "1"})
    products_directory = support.swift_build(
        configuration,
        product="swift-bundler",
        arch=arch,
        prebuilts=True,
        environment=env,
        skip_build=skip_build,
    )
    binary = products_directory / "swift-bundler"
    support.require_file(binary, f"built {arch} swift-bundler executable")

    support.copy_file(binary, destination, mode=0o755)
    return destination


def sign_binary(binary: Path) -> None:
    identity = os.environ.get("SBUN_APP_IDENTITY")
    arguments = ["codesign", "--force"]
    if identity:
        arguments += ["--options", "runtime", "--timestamp"]
    arguments += ["--sign", identity or "-", str(binary)]
    support.run(arguments)


def build_universal(
    output_dir: Path,
    version: str,
    configuration: str,
    *,
    skip_build: bool,
) -> Path:
    work_directory = support.ensure_directory(output_dir / "work")
    binaries = [
        build_architecture(
            arch,
            work_directory,
            configuration,
            skip_build=skip_build,
        )
        for arch in ARCHITECTURES
    ]

    universal = output_dir / f"swift-bundler-{version}-macos-universal"
    support.remove_path(universal)
    support.run(
        [
            "lipo",
            "-create",
            "-output",
            str(universal),
        ]
        + [str(binary) for binary in binaries]
    )
    os.chmod(universal, 0o755)

    support.run(["lipo", "-info", str(universal)])
    support.run(["file", str(universal)])
    support.run(["otool", "-l", str(universal)], capture=True)

    sign_binary(universal)

    support.write_checksum(universal)

    logging.info("Created universal binary %s", universal)
    return universal


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="macos/build.py",
        description="Build Swift Bundler's macOS .pkg installer.",
    )
    parser.add_argument(
        "--version",
        help="Override the version (defaults to parsing from Sources/SwiftBundler/SwiftBundler.swift)",
    )
    parser.add_argument(
        "--output-dir",
        help="Output root (defaults to Distribution/out)",
    )
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="Reuse existing per-architecture binaries under <output>/macos/work",
    )
    parser.add_argument(
        "--configuration",
        default="release",
        help="Swift build configuration (default: release)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the commands that would be run",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable debug logging",
    )
    return parser


def print_plan(version: str, output_dir: Path, configuration: str) -> None:
    env = "SBUN_NO_SCHEMA_GEN=1"
    for arch in ARCHITECTURES:
        logging.info("+ %s", env)
        support.log_command(
            support.swift_build_arguments(
                configuration,
                product="swift-bundler",
                arch=arch,
                prebuilts=True,
            )
        )
    support.log_command(
        [
            "lipo",
            "-create",
            "-output",
            f"<swift-bundler-{version}-macos-universal>",
            "<arm64>",
            "<x86_64>",
        ]
    )
    support.log_command(
        [
            "codesign",
            "--force",
            "--sign",
            "<identity or ->",
            f"<swift-bundler-{version}-macos-universal>",
        ]
    )
    logging.info(
        "Would render distribution.xml and run pkgbuild/productbuild in %s", output_dir
    )
    logging.info(
        "Would emit swift-bundler-%s-macos-universal and its .pkg", version
    )


def main() -> int:
    if platform.system() != "Darwin":
        raise support.PackagingError("macOS packaging is only supported on macOS hosts.")

    parser = create_parser()
    arguments = parser.parse_args()
    support.setup_logging(arguments.verbose)

    version = support.resolve_version(arguments.version)
    output_dir = support.resolve_output_dir(arguments.output_dir, "macos")

    logging.info("Swift Bundler %s for macOS (universal)", version)

    if arguments.dry_run:
        print_plan(version, output_dir, arguments.configuration)
        return 0

    universal = build_universal(
        output_dir,
        version,
        arguments.configuration,
        skip_build=arguments.skip_build,
    )
    installer = pkg.build_pkg(universal, output_dir, version)
    logging.info("Artifacts:")
    logging.info("  %s", universal)
    logging.info("  %s", installer)
    return 0


if __name__ == "__main__":
    sys.exit(support.cli_entry(main))
