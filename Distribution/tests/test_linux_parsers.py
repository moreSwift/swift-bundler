from __future__ import annotations

import unittest
from pathlib import Path
import sys

DISTRIBUTION_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(DISTRIBUTION_ROOT))

from linux import staging


class LinuxParserTests(unittest.TestCase):
    def test_parse_ldd_output(self) -> None:
        fixture = (
            DISTRIBUTION_ROOT
            / "tests"
            / "fixtures"
            / "ldd-ubuntu-22.04.txt"
        ).read_text(encoding="utf-8")
        dependencies, missing = staging.parse_ldd_output(fixture)

        self.assertEqual(missing, ["libmissing.so.1"])
        self.assertEqual(
            [soname for soname, _ in dependencies],
            [
                "libswiftCore.so.1",
                "libFoundation.so.6",
                "libcurl.so.4",
                "libc.so.6",
            ],
        )


if __name__ == "__main__":
    unittest.main()
