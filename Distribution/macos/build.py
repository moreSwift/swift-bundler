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
from macos import pkg, signing  # noqa: E402

ARCHITECTURES = ("arm64", "x86_64")
MACOS_DEPLOYMENT_TARGET = "10.15"


def metadata_compile_arguments(arch: str) -> list:
    """Return the swiftc flags needed to compile metadata for `arch`."""
    sdk = support.command_stdout(["xcrun", "--show-sdk-path"])
    target = f"{arch}-apple-macosx{MACOS_DEPLOYMENT_TARGET}"
    return ["-target", target, "-sdk", sdk]


def build_architecture(
    arch: str,
    work_directory: Path,
    configuration: str,
    *,
    skip_build: bool,
    metadata_object: Path,
) -> Path:
    destination = work_directory / f"swift-bundler-{arch}"

    env = support.build_environment({"SBUN_NO_SCHEMA_GEN": "1"})
    products_directory = support.swift_build(
        configuration,
        product="swift-bundler",
        arch=arch,
        prebuilts=True,
        defines=["SWIFT_BUNDLER_METADATA"],
        linker_inputs=[metadata_object],
        environment=env,
        skip_build=False,
    )
    binary = products_directory / "swift-bundler"
    support.require_file(binary, f"built {arch} swift-bundler executable")

    support.copy_file(binary, destination, mode=0o755)
    return destination


def build_universal(
    output_dir: Path,
    version: str,
    configuration: str,
    *,
    skip_build: bool,
    installation_method: str,
) -> Path:
    work_directory = support.ensure_directory(output_dir / "work")
    environment = support.build_environment({"SBUN_NO_SCHEMA_GEN": "1"})
    metadata_objects = {
        arch: support.compile_installation_metadata(
            work_directory / f"metadata-{arch}",
            installation_method,
            version,
            arguments=metadata_compile_arguments(arch),
            environment=environment,
        )
        for arch in ARCHITECTURES
    }
    binaries = [
        build_architecture(
            arch,
            work_directory,
            configuration,
            skip_build=skip_build,
            metadata_object=metadata_objects[arch],
        )
        for arch in ARCHITECTURES
    ]

    universal = work_directory / "swift-bundler-universal"
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
        help=(
            "Avoid recompiling; each artifact is still re-linked to stamp its "
            "installation method"
        ),
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

    cli_universal = build_universal(
        output_dir,
        version,
        arguments.configuration,
        skip_build=arguments.skip_build,
        installation_method="loose",
    )

    cli_binary = output_dir / f"swift-bundler-{version}-macos-universal"
    support.copy_file(cli_universal, cli_binary, mode=0o755)
    signing.sign_binary(cli_binary)
    # The checksum must be taken after signing, because signing rewrites the
    # executable.
    support.write_checksum(cli_binary)
    logging.info("Created universal binary %s", cli_binary)

    pkg_universal = build_universal(
        output_dir,
        version,
        arguments.configuration,
        skip_build=arguments.skip_build,
        installation_method="pkg",
    )
    installer = pkg.build_pkg(pkg_universal, output_dir, version)
    logging.info("Artifacts:")
    logging.info("  %s", cli_binary)
    logging.info("  %s", installer)
    return 0


if __name__ == "__main__":
    sys.exit(support.cli_entry(main))
