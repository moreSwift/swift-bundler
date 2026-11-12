"""Linux build and staging logic using the Static Swift Linux SDK."""

from __future__ import annotations

import logging
import os
import platform
import re
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Tuple

from common import support

STATIC_SDK_TRIPLES = {
    "x86_64": "x86_64-swift-linux-musl",
    "arm64": "aarch64-swift-linux-musl",
}

# The Static Linux SDK artifact has used both bundle versions. Newer
# toolchains use 0.1.0; keep 0.0.1 as a fallback for older releases.
STATIC_SDK_BUNDLE_VERSIONS = ("0.1.0", "0.0.1")

YAMS_PATCH_MARKER = "import var _float.DBL_DECIMAL_DIG"


def cross_compiling() -> bool:
    return platform.system() == "Darwin"


@dataclass
class Stage:
    root: Path
    main_executable: Path
    version: str
    arch: str


def static_sdk_selector(arch: str) -> str:
    try:
        return STATIC_SDK_TRIPLES[arch]
    except KeyError as error:
        raise support.PackagingError(
            f"No Static Linux SDK target triple is defined for {arch}"
        ) from error


def static_sdk_artifact_url(version: str, bundle_version: str) -> str:
    name = (
        f"swift-{version}-RELEASE_static-linux-"
        f"{bundle_version}.artifactbundle.tar.gz"
    )
    return (
        f"https://download.swift.org/swift-{version}-release/static-sdk/"
        f"swift-{version}-RELEASE/{name}"
    )


def swift_version() -> str:
    output = support.command_stdout(
        ["swift", "--version"],
        env=support.toolchain_environment(),
    )
    match = re.search(r"Swift version (\d+\.\d+\.\d+)", output)
    if match is None:
        raise support.PackagingError(
            f"Failed to determine the Swift version from: {output}"
        )
    return match.group(1)


def installed_static_sdk_ids() -> List[str]:
    result = support.run(
        ["swift", "sdk", "list"],
        capture=True,
        check=False,
        env=support.toolchain_environment(),
    )
    output = ((result.stdout or "") + (result.stderr or "")).strip()
    return [
        line.strip()
        for line in output.splitlines()
        if "static-linux" in line and line.strip()
    ]


def ensure_static_linux_sdk(output_dir: Path, arch: str) -> str:
    """Return the `--swift-sdk` selector, installing the SDK if necessary."""
    override = os.environ.get("SBUN_STATIC_LINUX_SDK")
    if override:
        logging.info("Using Static Linux SDK from SBUN_STATIC_LINUX_SDK")
        return override

    selector = static_sdk_selector(arch)
    version = swift_version()
    marker = f"swift-{version}-RELEASE_static-linux"
    if any(marker in sdk_id for sdk_id in installed_static_sdk_ids()):
        logging.info("Using installed Static Linux SDK for Swift %s", version)
        return selector

    cache_directory = support.ensure_directory(output_dir / "sdk")
    artifact: Optional[Path] = None
    for bundle_version in STATIC_SDK_BUNDLE_VERSIONS:
        name = (
            f"swift-{version}-RELEASE_static-linux-"
            f"{bundle_version}.artifactbundle.tar.gz"
        )
        candidate = cache_directory / name
        if candidate.is_file():
            artifact = candidate
            break

        url = static_sdk_artifact_url(version, bundle_version)
        temporary = candidate.with_name(candidate.name + ".part")
        try:
            support.download_file(url, temporary)
        except support.PackagingError as error:
            logging.debug("Static SDK download failed: %s", error)
            continue
        temporary.rename(candidate)
        artifact = candidate
        break

    if artifact is None:
        raise support.PackagingError(
            f"Could not find or download a Static Linux SDK for Swift {version}. "
            "Set SBUN_STATIC_LINUX_SDK to an installed SDK selector to skip "
            "the download."
        )

    logging.info("Installing Static Linux SDK %s", artifact.name)
    support.run(
        ["swift", "sdk", "install", str(artifact)],
        env=support.toolchain_environment(),
    )

    if not any(marker in sdk_id for sdk_id in installed_static_sdk_ids()):
        raise support.PackagingError(
            f"Static Linux SDK for Swift {version} was installed but is not "
            "visible to `swift sdk list`."
        )
    return selector


def _patch_yams_for_static_sdk() -> None:
    """Apply Yams' upstream Musl ambiguity workaround when needed.

    Yams 5.x uses the unqualified ``DBL_DECIMAL_DIG`` global, which is
    ambiguous in the Static Linux SDK because both ``_float`` and
    ``_Builtin_float`` export it. Upstream fixed this in Yams 6.2.2 with an
    explicit import. We apply the same one-line workaround to the resolved
    checkout without changing the repository's dependency pins.

    Upgrading to Yams 6.2.2 is currently impossible because the ``XcodeGen``
    dependency still requires Yams 5.x, and SwiftPM resolves one version for
    the whole graph.
    """
    representer = (
        support.REPO_ROOT
        / ".build"
        / "checkouts"
        / "Yams"
        / "Sources"
        / "Yams"
        / "Representer.swift"
    )
    if not representer.is_file():
        return

    contents = representer.read_text(encoding="utf-8")
    if YAMS_PATCH_MARKER in contents:
        return

    # SwiftPM checkouts are often read-only.
    os.chmod(representer, 0o644)

    import_statement = "import Foundation\n"
    if import_statement not in contents:
        logging.warning("Could not apply the Yams static-SDK workaround")
        return

    workaround = (
        "import Foundation\n"
        "\n"
        "#if canImport(Musl)\n"
        "// Workaround for conflict between _float and _Builtin_float in the "
        "Static Linux SDK.\n"
        "import var _float.DBL_DECIMAL_DIG\n"
        "#endif\n"
    )
    representer.write_text(
        contents.replace(import_statement, workaround, 1),
        encoding="utf-8",
    )
    logging.info("Applied Yams Static Linux SDK compatibility workaround")


def _patch_tomlkit_for_static_sdk() -> None:
    """Add Musl imports to TOMLKit's older platform conditionals.

    TOMLKit 0.7.2 predates Musl/Static Linux SDK support. Its eight platform
    blocks import Glibc but fall through to ``#error`` when building with Musl.
    """
    sources = (
        support.REPO_ROOT
        / ".build"
        / "checkouts"
        / "TOMLKit"
        / "Sources"
        / "TOMLKit"
    )
    if not sources.is_dir():
        return

    old = "#elseif canImport(Glibc)\n\timport Glibc\n"
    new = (
        "#elseif canImport(Glibc)\n"
        "\timport Glibc\n"
        "#elseif canImport(Musl)\n"
        "\timport Musl\n"
    )

    patched = 0
    for path in sources.rglob("*.swift"):
        contents = path.read_text(encoding="utf-8")
        if "canImport(Musl)" in contents or old not in contents:
            continue
        os.chmod(path, 0o644)
        path.write_text(contents.replace(old, new, 1), encoding="utf-8")
        patched += 1

    if patched:
        logging.info(
            "Applied TOMLKit Static Linux SDK compatibility workaround to "
            "%d file(s)",
            patched,
        )


CROSS_PROBE_PACKAGE = """// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "static-linux-probe",
    targets: [.executableTarget(name: "probe")]
)
"""

CROSS_PROBE_SOURCE = """import Foundation

print(FileManager.default.currentDirectoryPath)
"""


def verify_cross_toolchain(selector: str, env: dict) -> None:
    """Compile and link a tiny Foundation program for the Static Linux SDK.

    Xcode's Swift toolchain cannot read the SDK's prebuilt modules (they are
    built by the open-source toolchain) and lacks the Linux linker, so the real
    build would fail minutes in with an opaque serialized-module error. Probe
    first so failures are immediate and explain the fix; linking also proves the
    toolchain's `swift-autolink-extract` and `ld.lld` are reachable.
    """
    with tempfile.TemporaryDirectory(
        prefix="swift-bundler-cross-probe-"
    ) as temporary:
        root = Path(temporary)
        sources = root / "Sources" / "probe"
        support.ensure_directory(sources)
        (root / "Package.swift").write_text(CROSS_PROBE_PACKAGE, encoding="utf-8")
        (sources / "main.swift").write_text(CROSS_PROBE_SOURCE, encoding="utf-8")

        result = support.run(
            ["swift", "build", "-c", "debug", "--swift-sdk", selector],
            cwd=root,
            env=env,
            capture=True,
            check=False,
        )
        if result.returncode == 0:
            return

        output = ((result.stdout or "") + (result.stderr or "")).strip()
        raise support.PackagingError(
            "Cannot cross-compile for Linux with the selected Swift toolchain.\n"
            f"Probe output:\n{output}\n\n"
            "The Static Linux SDK ships modules built by the open-source Swift "
            "toolchain. Xcode's toolchain cannot read them (and ships without "
            "the Linux linker). Install the matching open-source toolchain and "
            "select it with SBUN_TOOLCHAIN_BIN, for example:\n"
            "  swiftly install 6.3.1\n"
            "  export SBUN_TOOLCHAIN_BIN="
            '"$HOME/Library/Developer/Toolchains/'
            'swift-6.3.1-RELEASE.xctoolchain/usr/bin"'
        )


def build_swift_bundler(
    version: str,
    arch: str,
    output_dir: Path,
    configuration: str = "release",
    skip_build: bool = False,
) -> Tuple[Path, Path]:
    selector = ensure_static_linux_sdk(output_dir, arch)
    env = support.build_environment({"SBUN_NO_SCHEMA_GEN": "1"})
    if cross_compiling() and not skip_build:
        verify_cross_toolchain(selector, env)

    build_command = [
        "swift",
        "build",
        "-c",
        configuration,
        "--product",
        "swift-bundler",
        "--swift-sdk",
        selector,
        "--disable-experimental-prebuilts",
    ]
    show_path_command = [
        "swift",
        "build",
        "--show-bin-path",
        "-c",
        configuration,
        "--swift-sdk",
        selector,
        "--disable-experimental-prebuilts",
    ]

    if not skip_build:
        # Ensure checkouts exist before applying the Yams workaround. SwiftPM
        # will not overwrite an existing checkout during the subsequent build.
        support.run(["swift", "package", "resolve"], env=env)
        _patch_yams_for_static_sdk()
        _patch_tomlkit_for_static_sdk()
        support.run(build_command, env=env)

    output = support.command_stdout(show_path_command, env=env)
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    if not lines:
        raise support.PackagingError("`swift build --show-bin-path` produced no output")
    products_directory = Path(lines[-1])
    binary = products_directory / "swift-bundler"
    support.require_file(binary, "built swift-bundler executable")

    if cross_compiling():
        logging.info(
            "Built Swift Bundler %s for Linux %s with the Static Linux SDK",
            version,
            arch,
        )
    else:
        built_version = support.command_stdout([binary, "--version"])
        logging.info("Built %s with the Static Linux SDK", built_version)
    return binary, products_directory


def build_host_completion_binary(
    version: str,
    configuration: str = "release",
) -> Path:
    """Build a host-native binary for generating completion scripts."""
    override = os.environ.get("SBUN_COMPLETIONS_BINARY")
    if override:
        binary = Path(override).expanduser().resolve()
        support.require_file(binary, "completion-generation binary")
        return binary

    logging.info("Building a host binary to generate shell completions")
    env = support.build_environment({"SBUN_NO_SCHEMA_GEN": "1"})
    support.run(
        [
            "swift",
            "build",
            "-c",
            configuration,
            "--product",
            "swift-bundler",
        ],
        env=env,
    )
    output = support.command_stdout(
        ["swift", "build", "--show-bin-path", "-c", configuration],
        env=env,
    )
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    if not lines:
        raise support.PackagingError(
            "`swift build --show-bin-path` produced no output for the host "
            "completion binary"
        )
    binary = Path(lines[-1]) / "swift-bundler"
    support.require_file(binary, "host completion-generation binary")
    built_version = support.command_stdout([binary, "--version"])
    if version not in built_version:
        logging.warning(
            "Host completion binary reports %s (expected %s)",
            built_version,
            version,
        )
    return binary


def _generate_completion(binary: Path, shell: str) -> str:
    result = support.run(
        [str(binary), "--generate-completion-script", shell], capture=True
    )
    return result.stdout or ""


def _assert_statically_linked(binary: Path) -> None:
    description = support.command_stdout(["file", str(binary)])
    if "statically linked" not in description:
        raise support.PackagingError(
            "Expected a statically linked executable from the Static Linux "
            f"SDK, but `file` reported:\n{description}"
        )

    if cross_compiling():
        return

    result = support.run(["ldd", str(binary)], capture=True, check=False)
    combined = (result.stdout or "") + (result.stderr or "")
    if "not a dynamic executable" not in combined and "statically linked" not in combined:
        raise support.PackagingError(
            "Expected `ldd` to report a static executable, but got:\n" + combined
        )


def stage_linux_tree(
    binary: Path,
    output_dir: Path,
    version: str,
    arch: str,
    completion_binary: Optional[Path] = None,
) -> Stage:
    stage_root = output_dir / f"stage-{arch}"
    support.remove_path(stage_root)
    binary_directory = support.ensure_directory(stage_root / "usr" / "bin")
    docs_directory = support.ensure_directory(
        stage_root / "usr" / "share" / "doc" / "swift-bundler"
    )
    bash_directory = support.ensure_directory(
        stage_root / "usr" / "share" / "bash-completion" / "completions"
    )
    zsh_directory = support.ensure_directory(
        stage_root / "usr" / "share" / "zsh" / "vendor-completions"
    )
    fish_directory = support.ensure_directory(
        stage_root / "usr" / "share" / "fish" / "vendor_completions.d"
    )

    main_executable = binary_directory / "swift-bundler"
    support.copy_file(binary, main_executable, mode=0o755)
    _assert_statically_linked(main_executable)

    # `sbun` is the short alias for `swift-bundler`.
    os.symlink("swift-bundler", binary_directory / "sbun")

    completions = {
        "bash": (
            bash_directory / "swift-bundler",
            bash_directory / "sbun",
            0o644,
        ),
        "zsh": (
            zsh_directory / "_swift-bundler",
            zsh_directory / "_sbun",
            0o644,
        ),
        "fish": (
            fish_directory / "swift-bundler.fish",
            fish_directory / "sbun.fish",
            0o644,
        ),
    }
    completion_source = completion_binary or main_executable
    for shell, (destination, alias_destination, mode) in completions.items():
        contents = _generate_completion(completion_source, shell)
        destination.write_text(contents, encoding="utf-8")
        alias_contents = support.rename_completion_script(
            contents, "swift-bundler", "sbun"
        )
        alias_destination.write_text(alias_contents, encoding="utf-8")
        os.chmod(destination, mode)
        os.chmod(alias_destination, mode)

    support.copy_file(
        support.REPO_ROOT / "LICENSE", docs_directory / "LICENSE", mode=0o644
    )
    support.copy_file(
        support.REPO_ROOT / "README.md", docs_directory / "README.md", mode=0o644
    )
    support.copy_file(
        support.DISTRIBUTION_ROOT / "linux" / "THIRD_PARTY_NOTICES.md",
        docs_directory / "THIRD_PARTY_NOTICES.md",
        mode=0o644,
    )

    if not cross_compiling():
        support.run([str(main_executable), "--version"])

    return Stage(
        root=stage_root,
        main_executable=main_executable,
        version=version,
        arch=arch,
    )


def stage_linux_loose(stage: Stage, output_dir: Path) -> Tuple[Path, Path]:
    name = f"swift-bundler-{stage.version}-linux-{stage.arch}"
    root = output_dir / name
    support.remove_path(root)
    support.ensure_directory(root)

    support.copy_tree(stage.root / "usr" / "bin", root / "bin", symlinks=True)
    support.copy_tree(stage.root / "usr" / "share", root / "share", symlinks=True)

    readme = f"""Swift Bundler {stage.version} (Linux {stage.arch})
====================================================

This distribution was built with the Static Swift Linux SDK. The binary is
fully statically linked, so it does not require the Swift runtime or any system
libraries.

Run Swift Bundler directly:

    ./bin/swift-bundler --help
    ./bin/sbun --help

Or install swift-bundler and sbun to a directory on your path:

    sudo cp swift-bundler sbun /usr/local/bin

Or add this directory's `bin` folder to PATH:

    export PATH="$PWD/bin:$PATH"
    swift-bundler --version
    sbun --version

`sbun` is a symlink to `swift-bundler`. The shell completion scripts live
under `share/`.
"""
    (root / "README.md").write_text(readme, encoding="utf-8")

    archive = output_dir / f"{name}.tar.gz"
    support.tar_directory(root, archive)
    return root, archive


def print_plan(
    version: str,
    arch: str,
    output_dir: Path,
    *,
    configuration: str = "release",
) -> None:
    env_note = "SBUN_NO_SCHEMA_GEN=1"
    logging.info("+ %s", env_note)
    if cross_compiling():
        logging.info(
            "Would cross-compile on macOS using the Static Linux SDK and an "
            "open-source Swift toolchain"
        )
    logging.info("Would ensure the Static Linux SDK for Swift is installed")
    support.log_command(
        [
            "swift",
            "build",
            "-c",
            configuration,
            "--product",
            "swift-bundler",
            "--swift-sdk",
            static_sdk_selector(arch),
            "--disable-experimental-prebuilts",
        ]
    )
    support.log_command(
        [
            "swift",
            "build",
            "--show-bin-path",
            "-c",
            configuration,
            "--swift-sdk",
            static_sdk_selector(arch),
        ]
    )
    logging.info("Would stage %s for Linux %s in %s", version, arch, output_dir)
