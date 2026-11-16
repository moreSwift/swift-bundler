from __future__ import annotations

import json
import re
import tempfile
import unittest
from pathlib import Path
from unittest import mock
import sys

DISTRIBUTION_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(DISTRIBUTION_ROOT))

from common import support


def embedded_json(code: str) -> bytes:
    """Extract the metadata byte array from generated Swift source."""
    start = code.index("= [[") + len("= [[")
    end = code.index("]]", start)
    return bytes(int(number) for number in re.findall(r"\d+", code[start:end]))


class InstallationMetadataTests(unittest.TestCase):
    def test_generated_json_records_the_installation_method(self) -> None:
        code = support.installation_metadata_code("rpm", "1.2.3")
        document = json.loads(embedded_json(code))
        self.assertEqual(
            document["appIdentifier"],
            support.INSTALLATION_METADATA_IDENTIFIER,
        )
        self.assertEqual(document["appVersion"], "1.2.3")
        self.assertEqual(
            document["additionalMetadata"]["installationMethod"], "rpm"
        )

    def test_generated_code_defines_the_runtime_symbols(self) -> None:
        code = support.installation_metadata_code("pkg", "1.2.3")
        self.assertIn('@_cdecl("_getSwiftBundlerMetadata")', code)
        self.assertIn('@_silgen_name("sbun_getMetadata")', code)
        # The global is mutable state, which Swift 6 requires to be annotated.
        self.assertIn("nonisolated(unsafe)", code)

    def test_compiles_the_object_with_the_given_arguments(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with mock.patch.object(support, "run") as run:
                object_file = support.compile_installation_metadata(
                    directory,
                    "deb",
                    "1.2.3",
                    swiftc=["/toolchain/swiftc"],
                    arguments=["-target", "x86_64-swift-linux-musl"],
                )

            self.assertEqual(
                object_file, directory / "installation-metadata-deb.o"
            )
            source = directory / "installation-metadata-deb.swift"
            self.assertTrue(source.is_file())
            document = json.loads(
                embedded_json(source.read_text(encoding="utf-8"))
            )
            self.assertEqual(
                document["additionalMetadata"]["installationMethod"], "deb"
            )
            run.assert_called_once_with(
                [
                    "/toolchain/swiftc",
                    "-parse-as-library",
                    "-c",
                    "-o",
                    str(object_file),
                    str(source),
                    "-target",
                    "x86_64-swift-linux-musl",
                ],
                env=None,
            )

    def test_swift_build_links_the_metadata_object(self) -> None:
        arguments = support.swift_build_arguments(
            "release", linker_inputs=[Path("/tmp/metadata.o")]
        )
        self.assertEqual(arguments[-2:], ["-Xlinker", "/tmp/metadata.o"])

    def test_no_metadata_is_linked_by_default(self) -> None:
        arguments = support.swift_build_arguments("release")
        self.assertNotIn("-Xlinker", arguments)


if __name__ == "__main__":
    unittest.main()
