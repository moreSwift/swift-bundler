#!/usr/bin/env python3
"""Run Swift Bundler's distribution unit tests."""

from __future__ import annotations

import argparse
import logging
import sys
import unittest
from pathlib import Path

DISTRIBUTION_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(DISTRIBUTION_ROOT))

from common import support  # noqa: E402

TESTS_DIRECTORY = DISTRIBUTION_ROOT / "tests"


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="test.py",
        description="Discover and run Swift Bundler's distribution unit tests.",
    )
    parser.add_argument(
        "--pattern",
        default="test_*.py",
        help="Only load test files matching this glob (default: test_*.py)",
    )
    parser.add_argument(
        "--failfast",
        action="store_true",
        help="Stop after the first failure",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Show each test name",
    )
    return parser


def main() -> int:
    arguments = create_parser().parse_args()
    support.setup_logging()

    loader = unittest.TestLoader()
    suite = loader.discover(
        start_dir=str(TESTS_DIRECTORY),
        pattern=arguments.pattern,
        top_level_dir=str(DISTRIBUTION_ROOT),
    )

    count = suite.countTestCases()
    if count == 0:
        logging.error(
            "No tests found in %s matching %s",
            support.relative_to_repo(TESTS_DIRECTORY),
            arguments.pattern,
        )
        return 1

    logging.info(
        "Running %d test(s) from %s",
        count,
        support.relative_to_repo(TESTS_DIRECTORY),
    )
    runner = unittest.TextTestRunner(
        verbosity=2 if arguments.verbose else 1,
        failfast=arguments.failfast,
    )
    return 0 if runner.run(suite).wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(support.cli_entry(main))
