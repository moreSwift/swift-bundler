from __future__ import annotations

import unittest
from pathlib import Path
import sys

DISTRIBUTION_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(DISTRIBUTION_ROOT))

from linux import staging


class LinuxStaticSDKTests(unittest.TestCase):
    def test_selectors(self) -> None:
        self.assertEqual(
            staging.static_sdk_selector("x86_64"),
            "x86_64-swift-linux-musl",
        )
        self.assertEqual(
            staging.static_sdk_selector("arm64"),
            "aarch64-swift-linux-musl",
        )

    def test_artifact_url(self) -> None:
        self.assertEqual(
            staging.static_sdk_artifact_url("6.3.3", "0.1.0"),
            "https://download.swift.org/swift-6.3.3-release/static-sdk/"
            "swift-6.3.3-RELEASE/"
            "swift-6.3.3-RELEASE_static-linux-0.1.0.artifactbundle.tar.gz",
        )


if __name__ == "__main__":
    unittest.main()
