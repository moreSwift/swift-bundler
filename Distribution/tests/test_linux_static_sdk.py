from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest import mock
import sys

DISTRIBUTION_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(DISTRIBUTION_ROOT))

from common import support
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


class StripTests(unittest.TestCase):
    def test_strips_on_native_linux(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            binary = Path(temporary) / "swift-bundler"
            binary.write_bytes(b"x" * 4096)

            with mock.patch.object(
                staging, "cross_compiling", return_value=False
            ), mock.patch.object(
                support, "require_command", return_value="/usr/bin/strip"
            ), mock.patch.object(support, "run") as run:
                staging._strip_linux_executable(binary)

            run.assert_called_once_with(
                ["/usr/bin/strip", "--strip-all", str(binary)]
            )

    def test_skipped_when_cross_compiling(self) -> None:
        with mock.patch.object(
            staging, "cross_compiling", return_value=True
        ), mock.patch.object(support, "run") as run:
            staging._strip_linux_executable(Path("/tmp/swift-bundler"))

        run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
