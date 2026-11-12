from __future__ import annotations

import subprocess
import tempfile
import unittest
import unittest.mock
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

    def test_rename_completion_script(self) -> None:
        script = (
            "#compdef swift-bundler\n"
            "_swift-bundler() { :; }\n"
            "complete -F _swift-bundler swift-bundler\n"
        )
        renamed = support.rename_completion_script(
            script, "swift-bundler", "sbun"
        )
        self.assertIn("#compdef sbun", renamed)
        self.assertIn("_sbun()", renamed)
        self.assertIn("complete -F _sbun sbun", renamed)
        self.assertNotIn("swift-bundler", renamed)

    def test_installed_size(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "a").write_bytes(b"x" * 1024)
            self.assertEqual(support.installed_size_kb(root), 1)


class SwiftBuildArgumentTests(unittest.TestCase):
    def test_minimal_build(self) -> None:
        self.assertEqual(
            support.swift_build_arguments("release"),
            ["swift", "build", "-c", "release"],
        )

    def test_show_bin_path_comes_before_options(self) -> None:
        self.assertEqual(
            support.swift_build_arguments("debug", show_bin_path=True),
            ["swift", "build", "-c", "debug", "--show-bin-path"],
        )

    def test_linux_cross_build(self) -> None:
        self.assertEqual(
            support.swift_build_arguments(
                "release",
                product="swift-bundler",
                swift_sdk="x86_64-swift-linux-musl",
                prebuilts=False,
            ),
            [
                "swift",
                "build",
                "-c",
                "release",
                "--product",
                "swift-bundler",
                "--swift-sdk",
                "x86_64-swift-linux-musl",
                "--disable-experimental-prebuilts",
            ],
        )

    def test_macos_architecture_build(self) -> None:
        self.assertEqual(
            support.swift_build_arguments(
                "release",
                product="swift-bundler",
                arch="arm64",
                prebuilts=True,
            ),
            [
                "swift",
                "build",
                "-c",
                "release",
                "--product",
                "swift-bundler",
                "--arch",
                "arm64",
                "--enable-experimental-prebuilts",
            ],
        )

    def test_prebuilts_are_left_alone_by_default(self) -> None:
        arguments = support.swift_build_arguments("release", prebuilts=None)
        self.assertNotIn("--enable-experimental-prebuilts", arguments)
        self.assertNotIn("--disable-experimental-prebuilts", arguments)

    def test_swift_build_queries_the_products_directory(self) -> None:
        calls = []

        def fake_run(arguments, **kwargs):
            calls.append(list(arguments))
            return subprocess.CompletedProcess(arguments, 0, "/tmp/products\n", "")

        with unittest.mock.patch.object(support, "run", side_effect=fake_run):
            directory = support.swift_build(
                "release",
                product="swift-bundler",
                swift_sdk="aarch64-swift-linux-musl",
                prebuilts=False,
            )

        self.assertEqual(directory, Path("/tmp/products"))
        self.assertEqual(
            calls[0],
            support.swift_build_arguments(
                "release",
                product="swift-bundler",
                swift_sdk="aarch64-swift-linux-musl",
                prebuilts=False,
            ),
        )
        self.assertEqual(
            calls[1],
            support.swift_build_arguments(
                "release",
                product="swift-bundler",
                swift_sdk="aarch64-swift-linux-musl",
                show_bin_path=True,
            ),
        )

    def test_swift_build_skip_build_only_queries(self) -> None:
        calls = []

        def fake_run(arguments, **kwargs):
            calls.append(list(arguments))
            return subprocess.CompletedProcess(arguments, 0, "/tmp/products\n", "")

        with unittest.mock.patch.object(support, "run", side_effect=fake_run):
            support.swift_build("release", skip_build=True)

        self.assertEqual(len(calls), 1)
        self.assertIn("--show-bin-path", calls[0])

    def test_swift_build_rejects_empty_output(self) -> None:
        def fake_run(arguments, **kwargs):
            return subprocess.CompletedProcess(arguments, 0, "", "")

        with unittest.mock.patch.object(support, "run", side_effect=fake_run):
            with self.assertRaises(support.PackagingError):
                support.swift_build("release", skip_build=True)


if __name__ == "__main__":
    unittest.main()
