from __future__ import annotations

import unittest
from pathlib import Path
import sys

DISTRIBUTION_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(DISTRIBUTION_ROOT))

from common import support
from windows import staging


class WindowsParserTests(unittest.TestCase):
    def test_parse_dumpbin_output(self) -> None:
        fixture = (
            DISTRIBUTION_ROOT / "tests" / "fixtures" / "dumpbin-x64.txt"
        ).read_text(encoding="utf-8")
        dependencies = staging.parse_dumpbin_output(fixture)

        self.assertEqual(
            dependencies,
            [
                "KERNEL32.dll",
                "swiftCore.dll",
                "Foundation.dll",
                "api-ms-win-crt-runtime-l1-1-0.dll",
            ],
        )

    def test_parse_dumpbin_output_without_section(self) -> None:
        with self.assertRaises(support.PackagingError):
            staging.parse_dumpbin_output("not a dumpbin report")


if __name__ == "__main__":
    unittest.main()
