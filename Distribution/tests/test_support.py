from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import sys

DISTRIBUTION_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(DISTRIBUTION_ROOT))

from common import support


class SupportTests(unittest.TestCase):
    def test_parse_version_from_source(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "SwiftBundler.swift"
            path.write_text(
                "private static let _version = Version(1, 2, 3)\n",
                encoding="utf-8",
            )
            self.assertEqual(support.parse_version_from_source(path), "1.2.3")

    def test_invalid_version_is_rejected(self) -> None:
        with self.assertRaises(support.PackagingError):
            support.resolve_version("1.2.3-beta")

    def test_arch_mappings(self) -> None:
        self.assertEqual(support.deb_arch("x86_64"), "amd64")
        self.assertEqual(support.deb_arch("arm64"), "arm64")
        self.assertEqual(support.rpm_arch("x86_64"), "x86_64")
        self.assertEqual(support.rpm_arch("arm64"), "aarch64")
        self.assertEqual(support.wix_arch("x86_64"), "x64")
        self.assertEqual(support.wix_arch("arm64"), "arm64")

    def test_render_template(self) -> None:
        rendered = support.render_template(
            "Version: @@VERSION@@\n$RPM_BUILD_ROOT\n%{_bindir}\n",
            {"VERSION": "1.2.3"},
        )
        self.assertIn("Version: 1.2.3", rendered)
        self.assertIn("$RPM_BUILD_ROOT", rendered)
        self.assertIn("%{_bindir}", rendered)

    def test_render_template_rejects_unresolved_tokens(self) -> None:
        with self.assertRaises(support.PackagingError):
            support.render_template("@@MISSING@@", {})

    def test_installed_size(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "a").write_bytes(b"x" * 1024)
            self.assertEqual(support.installed_size_kb(root), 1)


if __name__ == "__main__":
    unittest.main()
