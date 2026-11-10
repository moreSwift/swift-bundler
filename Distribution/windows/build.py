#!/usr/bin/env python3
"""Build Swift Bundler's Windows distribution artifacts."""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

DISTRIBUTION_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(DISTRIBUTION_ROOT))

from common import support  # noqa: E402
from windows import msi, staging  # noqa: E402


def add_common_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--version",
        help="Override the version (defaults to Sources/SwiftBundler/SwiftBundler.swift)",
    )
    parser.add_argument(
        "--output-dir",
        help="Output root (defaults to Distribution/out)",
    )
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="Use an existing release build",
    )
    parser.add_argument(
        "--configuration",
        default="release",
        help="Swift build configuration (default: release)",
    )
    parser.add_argument(
        "--arch",
        help="Target architecture: x86_64 or arm64 (default: x86_64)",
    )
    parser.add_argument(
        "--sign",
        action="store_true",
        help="Sign the executable and MSI with signtool",
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


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="windows/build.py",
        description="Build Swift Bundler's Windows distribution artifacts.",
    )
    subparsers = parser.add_subparsers(dest="target", required=True)
    for target, description in (
        ("zip", "Build the loose .zip distribution"),
        ("msi", "Build the WiX MSI installer"),
        ("all", "Build both the .zip and .msi"),
    ):
        subparser = subparsers.add_parser(target, help=description)
        add_common_options(subparser)
    return parser


def main() -> int:
    parser = create_parser()
    arguments = parser.parse_args()
    support.setup_logging(arguments.verbose)

    version = support.resolve_version(arguments.version)
    arch = support.resolve_arch(arguments.arch or "x86_64")
    output_dir = support.resolve_output_dir(arguments.output_dir, "windows")

    host = support.host_arch()
    if arch != host:
        raise support.PackagingError(
            f"Cross-architecture Windows packaging is not supported: host is "
            f"{host}, requested {arch}. Run the script on the target "
            "architecture."
        )

    logging.info("Swift Bundler %s for Windows %s", version, arch)

    if arguments.dry_run:
        staging.print_plan(
            version,
            arch,
            output_dir,
            configuration=arguments.configuration,
        )
        if arguments.target in ("zip", "all"):
            logging.info(
                "Would create swift-bundler-%s-windows-%s.zip in %s",
                version,
                arch,
                output_dir,
            )
        if arguments.target in ("msi", "all"):
            msi.print_plan(
                staging.Stage(
                    root=output_dir / f"stage-{arch}",
                    main_executable=output_dir / f"stage-{arch}" / "swift-bundler.exe",
                    version=version,
                    arch=arch,
                ),
                output_dir,
            )
        if arguments.sign:
            logging.info("Would sign the executable and MSI with signtool")
        return 0

    stage = staging.build_stage(
        version,
        arch,
        output_dir,
        configuration=arguments.configuration,
        skip_build=arguments.skip_build,
    )

    if arguments.sign:
        msi.sign_file(stage.main_executable)

    artifacts = []
    if arguments.target in ("zip", "all"):
        archive = output_dir / f"swift-bundler-{version}-windows-{arch}.zip"
        support.zip_directory(
            stage.root,
            archive,
            root_name=f"swift-bundler-{version}-windows-{arch}",
        )
        logging.info("Created %s", archive)
        artifacts.append(archive)

    if arguments.target in ("msi", "all"):
        installer = msi.build_msi(stage, output_dir)
        if arguments.sign:
            msi.sign_file(installer)
        artifacts.append(installer)

    if artifacts:
        logging.info("Artifacts:")
        for artifact in artifacts:
            logging.info("  %s", artifact)
    return 0


if __name__ == "__main__":
    sys.exit(support.cli_entry(main))
