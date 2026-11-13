#!/usr/bin/env python3
"""Build Swift Bundler's Linux distribution artifacts."""

from __future__ import annotations

import argparse
import logging
import platform
import sys
from pathlib import Path

DISTRIBUTION_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(DISTRIBUTION_ROOT))

from common import support  # noqa: E402
from linux import deb, loose, rpm, staging  # noqa: E402


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
        help=(
            "Target architecture: x86_64 or aarch64 (default: host, or "
            "x86_64 when cross-compiling on macOS)"
        ),
    )
    parser.add_argument(
        "--deb-revision",
        default="1",
        help="Debian package revision (default: 1)",
    )
    parser.add_argument(
        "--rpm-release",
        default="1",
        help="RPM package release (default: 1)",
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
        prog="linux/build.py",
        description="Build Swift Bundler's Linux distribution artifacts.",
    )
    subparsers = parser.add_subparsers(dest="target", required=True)
    for target, description in (
        ("loose", "Build the loose .tar.gz distribution"),
        ("deb", "Build the Debian package"),
        ("rpm", "Build the RPM package"),
        ("all", "Build the loose archive, .deb, and .rpm"),
    ):
        subparser = subparsers.add_parser(target, help=description)
        add_common_options(subparser)
    return parser


def main() -> int:
    parser = create_parser()
    arguments = parser.parse_args()
    support.setup_logging(arguments.verbose)

    version = support.resolve_version(arguments.version)
    host_is_macos = platform.system() == "Darwin"
    default_arch = "x86_64" if host_is_macos else None
    arch = support.resolve_arch(arguments.arch or default_arch)
    output_dir = support.resolve_output_dir(arguments.output_dir, "linux")

    if not host_is_macos:
        if platform.system() != "Linux":
            raise support.PackagingError(
                "Linux bundling is only supported on macOS and Linux hosts."
            )

        host = support.host_arch()
        if arch != host:
            raise support.PackagingError(
                f"Cross-architecture Linux packaging is not supported on this "
                f"host: host is {host}, requested {arch}. Run on macOS or on "
                "the target architecture."
            )
    else:
        logging.info(
            "Cross-compiling Linux artifacts on macOS for %s", arch
        )

    logging.info("Swift Bundler %s for Linux %s", version, arch)

    if arguments.dry_run:
        staging.print_plan(
            version,
            arch,
            output_dir,
            configuration=arguments.configuration,
        )
        if arguments.target in ("deb", "all"):
            logging.info(
                "Would build Debian package %s-%s in %s",
                version,
                arguments.deb_revision,
                output_dir,
            )
        if arguments.target in ("rpm", "all"):
            logging.info(
                "Would build RPM package %s-%s in %s",
                version,
                arguments.rpm_release,
                output_dir,
            )
        if arguments.target in ("loose", "all"):
            logging.info("Would build loose tarball in %s", output_dir)
        return 0

    binary, _products_directory = staging.build_swift_bundler(
        version,
        arch,
        output_dir,
        configuration=arguments.configuration,
        skip_build=arguments.skip_build,
    )
    completion_binary = None
    if staging.cross_compiling():
        completion_binary = staging.build_host_completion_binary(
            version,
            configuration=arguments.configuration,
        )

    stage = staging.stage_linux_tree(
        binary,
        output_dir,
        version,
        arch,
        completion_binary=completion_binary,
    )

    artifacts = []
    if arguments.target in ("loose", "all"):
        _, archive = loose.build_loose(stage, output_dir)
        artifacts.append(archive)
    if arguments.target in ("deb", "all"):
        artifacts.append(
            deb.build_deb(
                stage,
                output_dir,
                revision=arguments.deb_revision,
            )
        )
    if arguments.target in ("rpm", "all"):
        artifacts.append(
            rpm.build_rpm(
                stage,
                output_dir,
                release=arguments.rpm_release,
            )
        )

    if artifacts:
        logging.info("Artifacts:")
        for artifact in artifacts:
            logging.info("  %s", artifact)
    return 0


if __name__ == "__main__":
    sys.exit(support.cli_entry(main))
