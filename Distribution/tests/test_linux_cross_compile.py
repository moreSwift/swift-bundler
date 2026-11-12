from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock
import sys

DISTRIBUTION_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(DISTRIBUTION_ROOT))

from common import support
from linux import rpm, staging


class CrossToolchainProbeTests(unittest.TestCase):
    def test_successful_probe_returns_silently(self) -> None:
        completed = subprocess.CompletedProcess([], 0, "", "")
        with mock.patch.object(support, "run", return_value=completed):
            staging.verify_cross_toolchain("x86_64-swift-linux-musl", {})

    def test_failed_probe_explains_the_fix(self) -> None:
        completed = subprocess.CompletedProcess(
            [],
            1,
            "",
            "error: compiled module was created by an older version of the compiler",
        )
        with mock.patch.object(support, "run", return_value=completed):
            with self.assertRaises(support.PackagingError) as raised:
                staging.verify_cross_toolchain("x86_64-swift-linux-musl", {})

        message = str(raised.exception)
        self.assertIn("SBUN_TOOLCHAIN_BIN", message)
        self.assertIn("older version of the compiler", message)

    def test_probe_uses_a_foundation_program(self) -> None:
        captured = {}

        def fake_run(arguments, **kwargs):
            root = Path(kwargs["cwd"])
            captured["package"] = (root / "Package.swift").read_text(
                encoding="utf-8"
            )
            captured["source"] = (
                root / "Sources" / "probe" / "main.swift"
            ).read_text(encoding="utf-8")
            return subprocess.CompletedProcess([], 0, "", "")

        with mock.patch.object(support, "run", side_effect=fake_run):
            staging.verify_cross_toolchain("aarch64-swift-linux-musl", {})

        self.assertIn("executableTarget", captured["package"])
        self.assertIn("import Foundation", captured["source"])


class CrossRpmConfigTests(unittest.TestCase):
    def test_adds_buildarch_compat_for_foreign_architecture(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config = root / "config"
            config.mkdir()
            (config / "rpmrc").write_text("# stock\n", encoding="utf-8")

            rpmrc = rpm.write_cross_rpmrc(
                root / "rpmrc", config, "aarch64", "x86_64"
            )

            self.assertEqual(rpmrc.stat().st_mode & 0o777, 0o644)
            contents = rpmrc.read_text(encoding="utf-8")
            self.assertTrue(contents.startswith("# stock\n"))
            self.assertIn("buildarch_compat: aarch64: x86_64 noarch", contents)

    def test_leaves_matching_architecture_alone(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config = root / "config"
            config.mkdir()
            (config / "rpmrc").write_text("# stock\n", encoding="utf-8")

            rpmrc = rpm.write_cross_rpmrc(
                root / "rpmrc", config, "aarch64", "aarch64"
            )

            self.assertNotIn("buildarch_compat", rpmrc.read_text(encoding="utf-8"))

    def test_macos_arguments_target_linux_and_override_homebrew_prefixes(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config = root / "config"
            config.mkdir()
            (config / "rpmrc").write_text("# stock\n", encoding="utf-8")

            def fake_stdout(arguments, **kwargs):
                if arguments[-1] == "%{_rpmconfigdir}":
                    return str(config)
                return "aarch64"

            with mock.patch.object(
                support, "command_stdout", side_effect=fake_stdout
            ):
                arguments = rpm.macos_cross_arguments(root, "x86_64")

            self.assertEqual(arguments[0], "--rcfile")
            self.assertIn("x86_64-linux", arguments)
            joined = " ".join(arguments)
            self.assertIn("_prefix /usr", joined)
            self.assertIn("_datadir /usr/share", joined)
            self.assertNotIn("/opt/homebrew", joined)


if __name__ == "__main__":
    unittest.main()
