from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock
import sys

DISTRIBUTION_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(DISTRIBUTION_ROOT))

from linux import staging

SELECTOR = "x86_64-swift-linux-musl"
MARKER = "swift-6.4.2-RELEASE_static-linux"
SDK_ID = "swift-6.4.2-RELEASE_static-linux-0.1.0"


def create_static_sdk_bundle(
    root: Path,
    sdk_id: str = SDK_ID,
    selector: str = SELECTOR,
) -> Path:
    """Create a minimal `.artifactbundle` that resembles a Static Linux SDK."""
    bundle = root / f"{sdk_id}.artifactbundle"
    configuration = bundle / sdk_id / "swift-linux-musl"
    configuration.mkdir(parents=True)
    (bundle / "info.json").write_text(
        json.dumps(
            {
                "schemaVersion": "1.0",
                "artifacts": {
                    sdk_id: {
                        "type": "swiftSDK",
                        "version": "0.1.0",
                        "variants": [{"path": f"{sdk_id}/swift-linux-musl"}],
                    }
                },
            }
        ),
        encoding="utf-8",
    )
    (configuration / "swift-sdk.json").write_text(
        json.dumps(
            {
                "schemaVersion": "1.0",
                "targetTriples": {
                    selector: {
                        "sdkRootPath": "musl-1.2.5.sdk/x86_64",
                        "swiftResourcesPath": (
                            "musl-1.2.5.sdk/x86_64/usr/lib/swift_static"
                        ),
                    }
                },
            }
        ),
        encoding="utf-8",
    )
    return bundle


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

    def test_list_lines_keep_stdout_and_ignore_stderr(self) -> None:
        result = mock.Mock(
            stdout=f"\n{SDK_ID}\n\n  {SDK_ID}-other  \n",
            stderr="warning: this must be ignored\n",
        )
        with mock.patch.object(staging.support, "run", return_value=result):
            self.assertEqual(
                staging.swift_sdk_list_lines(),
                [SDK_ID, f"{SDK_ID}-other"],
            )

    def test_root_candidates_cover_known_locations(self) -> None:
        with tempfile.TemporaryDirectory() as temporary, mock.patch.object(
            Path, "home", return_value=Path(temporary)
        ), mock.patch.dict(
            os.environ,
            {"XDG_CONFIG_HOME": "/config", "XDG_DATA_HOME": "/data"},
            clear=False,
        ):
            roots = [str(root) for root in staging.swift_sdks_root_candidates()]

        # SwiftPM uses $XDG_CONFIG_HOME/swiftpm when the variable is set.
        self.assertEqual(roots[0], "/config/swiftpm/swift-sdks")
        self.assertIn(f"{temporary}/.swiftpm/swift-sdks", roots)
        self.assertIn(f"{temporary}/.config/swiftpm/swift-sdks", roots)
        self.assertIn(
            f"{temporary}/Library/org.swift.swiftpm/swift-sdks", roots
        )
        self.assertIn("/data/org.swift.swiftpm/swift-sdks", roots)
        self.assertIn(
            f"{temporary}/.local/share/org.swift.swiftpm/swift-sdks", roots
        )
        self.assertEqual(len(roots), len(set(roots)))

    def test_locate_sdk_in_dot_swiftpm(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            bundle = create_static_sdk_bundle(home / ".swiftpm" / "swift-sdks")
            base = bundle / SDK_ID / "swift-linux-musl"

            arguments = self.locate(home, [SDK_ID])

            self.assertEqual(
                [Path(arguments[1]), Path(arguments[5])],
                [
                    base / "musl-1.2.5.sdk" / "x86_64",
                    base / "musl-1.2.5.sdk" / "x86_64" / "usr/lib/swift_static",
                ],
            )
            self.assertEqual(arguments[2:4], ["-target", SELECTOR])

    def test_locate_sdk_in_xdg_config_directory(self) -> None:
        """GitHub's runners set XDG_CONFIG_HOME, moving SwiftPM's SDK directory."""
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary) / "home"
            config = Path(temporary) / "config"
            bundle = create_static_sdk_bundle(config / "swiftpm" / "swift-sdks")

            with mock.patch.object(
                Path, "home", return_value=home
            ), mock.patch.object(
                staging, "swift_sdk_list_lines", return_value=[SDK_ID]
            ), mock.patch.dict(
                os.environ,
                {"XDG_CONFIG_HOME": str(config), "XDG_DATA_HOME": ""},
                clear=False,
            ):
                arguments = staging.search_static_sdk(SELECTOR, MARKER).arguments

            self.assertTrue(Path(arguments[1]).is_relative_to(bundle))

    def test_locate_sdk_in_xdg_data_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            bundle = create_static_sdk_bundle(
                home / ".local" / "share" / "org.swift.swiftpm" / "swift-sdks"
            )

            arguments = self.locate(home, [SDK_ID])

            self.assertTrue(Path(arguments[1]).is_relative_to(bundle))

    def test_ignores_sdk_for_other_swift_version(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            create_static_sdk_bundle(
                home / ".swiftpm" / "swift-sdks",
                sdk_id="swift-6.3.3-RELEASE_static-linux-0.1.0",
            )

            self.assertIsNone(self.locate(home, [SDK_ID]))

    def test_ignores_bundle_without_matching_target(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            create_static_sdk_bundle(
                home / ".swiftpm" / "swift-sdks",
                selector="aarch64-swift-linux-musl",
            )

            self.assertIsNone(self.locate(home, [SDK_ID]))

    def test_ignores_bundles_outside_known_locations(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            create_static_sdk_bundle(home / "custom" / "swift-sdks")

            self.assertIsNone(self.locate(home, [SDK_ID]))

    def test_error_uses_search_results_without_searching_again(self) -> None:
        with tempfile.TemporaryDirectory() as temporary, mock.patch.object(
            Path, "home", return_value=Path(temporary)
        ), mock.patch.object(
            staging, "swift_sdk_list_lines", return_value=[SDK_ID]
        ) as listing, mock.patch.dict(
            os.environ, {"XDG_CONFIG_HOME": "", "XDG_DATA_HOME": ""}, clear=False
        ):
            create_static_sdk_bundle(
                Path(temporary) / ".swiftpm" / "swift-sdks",
                sdk_id="swift-6.3.3-RELEASE_static-linux-0.1.0",
            )
            search = staging.search_static_sdk(SELECTOR, MARKER)
            message = search.error_message()

        # The diagnostic is built from the recorded search, not a second pass.
        self.assertEqual(listing.call_count, 1)
        self.assertIsNone(search.arguments)
        self.assertIn(SELECTOR, message)
        self.assertIn(f"`swift sdk list` reported: {SDK_ID}", message)
        self.assertIn(
            f"{temporary}/.swiftpm/swift-sdks: "
            "swift-6.3.3-RELEASE_static-linux-0.1.0.artifactbundle",
            message,
        )
        self.assertIn("directory does not exist", message)

    def locate(
        self,
        home: Path,
        ids: list[str],
    ) -> list[str] | None:
        """Locate the SDK with an isolated home directory."""
        with mock.patch.object(Path, "home", return_value=home), mock.patch.object(
            staging, "swift_sdk_list_lines", return_value=ids
        ), mock.patch.dict(
            os.environ, {"XDG_CONFIG_HOME": "", "XDG_DATA_HOME": ""}, clear=False
        ):
            return staging.search_static_sdk(SELECTOR, MARKER).arguments


if __name__ == "__main__":
    unittest.main()
