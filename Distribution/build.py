#!/usr/bin/env python3
"""Cross-platform dispatcher for the Swift Bundler distribution scripts."""

from __future__ import annotations

import importlib
import sys
from pathlib import Path

DISTRIBUTION_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(DISTRIBUTION_ROOT))

from common import support  # noqa: E402

PLATFORMS = ("macos", "linux", "windows")


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print("usage: Distribution/build.py {macos|linux|windows} [options...]")
        return 0 if len(sys.argv) >= 2 else 2

    platform = sys.argv[1]
    if platform not in PLATFORMS:
        print(
            f"error: unknown platform '{platform}'; expected one of "
            + ", ".join(PLATFORMS),
            file=sys.stderr,
        )
        return 2

    module = importlib.import_module(f"{platform}.build")
    sys.argv = [sys.argv[0]] + sys.argv[2:]
    return int(module.main() or 0)


if __name__ == "__main__":
    sys.exit(support.cli_entry(main))
