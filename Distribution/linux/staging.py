"""Linux build and staging logic using the Static Swift Linux SDK."""

from __future__ import annotations

import json
import logging
import os
import platform
import re
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Set, Tuple

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


def swift_sdk_list_lines() -> List[str]:
    """Return the lines `swift sdk list` writes to stdout.

    SwiftPM lists one id per line, but it also writes warnings and the
    "No Swift SDKs are currently installed." notice to stdout, and writes
    nothing to stderr. Every non-empty line is kept as-is so nothing SwiftPM
    reports is silently dropped.
    """
    result = support.run(
        ["swift", "sdk", "list"],
        capture=True,
        check=False,
        env=support.toolchain_environment(),
    )
    return [
        line.strip()
        for line in (result.stdout or "").splitlines()
        if line.strip()
    ]


def swift_sdks_root_candidates() -> List[Path]:
    """Return the directories SwiftPM may store Swift SDKs in.

    SwiftPM uses ``$XDG_CONFIG_HOME/swiftpm/swift-sdks`` when ``XDG_CONFIG_HOME``
    is set (GitHub's runners set it), and otherwise
    ``<library directory>/org.swift.swiftpm/swift-sdks`` when Foundation reports
    a library directory, falling back to ``~/.swiftpm/swift-sdks``. Foundation's
    answer differs between platforms and builds, and the locations may be
    connected by symlinks, so every plausible location is considered.
    """
    home = Path.home()
    candidates: List[Path] = []

    config_home = os.environ.get("XDG_CONFIG_HOME", "").strip()
    if config_home:
        config_path = Path(config_home).expanduser()
        candidates += [
            config_path / "swiftpm" / "swift-sdks",
            config_path / "org.swift.swiftpm" / "swift-sdks",
        ]

    candidates += [
        home / ".swiftpm" / "swift-sdks",
        home / ".config" / "swiftpm" / "swift-sdks",
        home / "Library" / "org.swift.swiftpm" / "swift-sdks",
    ]

    data_home = os.environ.get("XDG_DATA_HOME", "").strip()
    if data_home:
        data_path = Path(data_home).expanduser()
        candidates += [
            data_path / "org.swift.swiftpm" / "swift-sdks",
            data_path / "swiftpm" / "swift-sdks",
        ]

    candidates += [
        home / ".local" / "share" / "org.swift.swiftpm" / "swift-sdks",
        home / ".local" / "share" / "swiftpm" / "swift-sdks",
    ]

    unique: List[Path] = []
    seen: Set[str] = set()
    for candidate in candidates:
        key = os.path.normpath(str(candidate))
        if key in seen:
            continue
        seen.add(key)
        unique.append(candidate)
    return unique


@dataclass
class StaticSDKSearch:
    """What a search for an installed Static Linux SDK found and looked at.

    The directories that were inspected are recorded so that a failure can be
    reported without searching the file system again.
    """

    selector: str
    # Lines printed by `swift sdk list` (ids, warnings, or its empty notice).
    reported: List[str]
    # Each searched directory and the `.artifactbundle` names it contains
    # (`None` when the directory doesn't exist).
    directories: List[Tuple[Path, Optional[List[str]]]]
    bundles: List[Path]
    arguments: Optional[List[str]] = None

    def error_message(self) -> str:
        """Describe why no usable SDK was found."""
        messages = ", ".join(self.reported) if self.reported else "nothing"
        lines = [
            f"Could not locate the installed Static Linux SDK for {self.selector}.",
            f"`swift sdk list` reported: {messages}",
            "Searched these Swift SDK directories:",
        ]
        for directory, bundles in self.directories:
            if bundles is None:
                detail = "directory does not exist"
            elif bundles:
                detail = ", ".join(bundles)
            else:
                detail = "no .artifactbundle bundles"
            lines.append(f"  {directory}: {detail}")

        if self.bundles:
            names = ", ".join(bundle.name for bundle in self.bundles)
            lines.append(
                f"None of the bundles for this Swift version ({names}) "
                f"provides {self.selector}."
            )

        lines.append(
            "Reinstall the SDK with `swift sdk install` if its bundle is "
            "missing or incomplete."
        )
        return "\n".join(lines)


def _bundle_artifact_ids(bundle: Path) -> List[str]:
    """Return the artifact ids declared by an `.artifactbundle`'s info.json."""
    try:
        document = json.loads((bundle / "info.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    artifacts = document.get("artifacts")
    if not isinstance(artifacts, dict):
        return []
    return [str(artifact_id) for artifact_id in artifacts]


def _is_static_sdk_bundle(bundle: Path, marker: str) -> bool:
    """Return whether a bundle holds the SDK for the given Swift version."""
    if marker in bundle.name:
        return True
    return any(marker in artifact_id for artifact_id in _bundle_artifact_ids(bundle))


def _bundles_in(directory: Path) -> List[str]:
    """Return the names of the `.artifactbundle` directories in ``directory``."""
    try:
        candidates = sorted(directory.glob("*.artifactbundle"))
    except OSError:
        return []

    names: List[str] = []
    for candidate in candidates:
        try:
            if candidate.is_dir():
                names.append(candidate.name)
        except OSError:
            continue
    return names


def _bundle_configurations(bundle: Path) -> List[Path]:
    """Return the `swift-sdk.json` files declared by an `.artifactbundle`."""
    try:
        document = json.loads((bundle / "info.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        document = {}

    configurations: List[Path] = []
    artifacts = document.get("artifacts")
    if isinstance(artifacts, dict):
        for artifact in artifacts.values():
            if not isinstance(artifact, dict):
                continue
            for variant in artifact.get("variants") or []:
                if not isinstance(variant, dict):
                    continue
                path = variant.get("path")
                if not isinstance(path, str) or not path:
                    continue
                configuration = bundle / path
                if configuration.suffix != ".json":
                    configuration = configuration / "swift-sdk.json"
                configurations.append(configuration)

    if configurations:
        return configurations

    # Fall back to the layout Swift SDK bundles have historically used.
    return sorted(bundle.glob("*/swift-linux-musl/swift-sdk.json")) + sorted(
        bundle.glob("*/swift-sdk.json")
    )


def _bundle_compile_arguments(bundle: Path, selector: str) -> Optional[List[str]]:
    """Return the swiftc flags for an SDK bundle, if it supports ``selector``."""
    for configuration in _bundle_configurations(bundle):
        try:
            document = json.loads(configuration.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        target = document.get("targetTriples", {}).get(selector)
        if target is None:
            continue
        try:
            sdk_root = target["sdkRootPath"]
            swift_resources = target["swiftResourcesPath"]
        except KeyError:
            continue
        base = configuration.parent
        return [
            "-sdk",
            str(base / sdk_root),
            "-target",
            selector,
            "-resource-dir",
            str(base / swift_resources),
        ]
    return None


def search_static_sdk(selector: str, marker: str) -> StaticSDKSearch:
    """Look for an installed bundle that provides ``selector``.

    Only the directories SwiftPM is known to use are inspected. The returned
    record describes what was searched so callers can report a useful error
    without inspecting the file system again.
    """
    search = StaticSDKSearch(
        selector=selector,
        reported=swift_sdk_list_lines(),
        directories=[],
        bundles=[],
    )

    for root in swift_sdks_root_candidates():
        if not root.is_dir():
            search.directories.append((root, None))
            continue

        names = _bundles_in(root)
        search.directories.append((root, names))
        for name in names:
            bundle = root / name
            if not _is_static_sdk_bundle(bundle, marker):
                continue
            search.bundles.append(bundle)
            arguments = _bundle_compile_arguments(bundle, selector)
            if arguments is not None:
                search.arguments = arguments
                return search

    return search


def ensure_static_linux_sdk(output_dir: Path, arch: str) -> str:
    """Return the `--swift-sdk` selector, installing the SDK if necessary."""
    override = os.environ.get("SBUN_STATIC_LINUX_SDK")
    if override:
        logging.info("Using Static Linux SDK from SBUN_STATIC_LINUX_SDK")
        return override

    selector = static_sdk_selector(arch)
    version = swift_version()
    marker = f"swift-{version}-RELEASE_static-linux"

    search = search_static_sdk(selector, marker)
    if search.arguments is not None:
        logging.info("Using installed Static Linux SDK for Swift %s", version)
        return selector

    if any(marker in line for line in search.reported):
        # SwiftPM knows about the SDK but we couldn't find it on disk. We have
        # to find it on disk in order to be able to reliably select it when
        # multiple Static Linux SDKs are installed. Reinstalling wouldn't help,
        # so report what was searched.
        raise support.PackagingError(search.error_message())

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

    search = search_static_sdk(selector, marker)
    if search.arguments is None:
        raise support.PackagingError(search.error_message())
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
            support.swift_build_arguments("debug", swift_sdk=selector),
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


# The cross-compilation sanity check only needs to run once per SDK.
_verified_static_sdks: Set[str] = set()


def _static_sdk_compile_arguments(selector: str) -> List[str]:
    """Return the swiftc flags needed to compile against an installed SDK."""
    marker = f"swift-{swift_version()}-RELEASE_static-linux"
    search = search_static_sdk(selector, marker)
    if search.arguments is not None:
        return search.arguments
    raise support.PackagingError(search.error_message())


def build_swift_bundler(
    version: str,
    arch: str,
    output_dir: Path,
    configuration: str = "release",
    skip_build: bool = False,
    installation_method: Optional[str] = None,
) -> Tuple[Path, Path]:
    selector = ensure_static_linux_sdk(output_dir, arch)
    env = support.build_environment({"SBUN_NO_SCHEMA_GEN": "1"})
    if cross_compiling() and selector not in _verified_static_sdks:
        verify_cross_toolchain(selector, env)
        _verified_static_sdks.add(selector)

    # The metadata object is linked into the executable, so each installation
    # method needs its own (re-)link.
    linker_inputs: List[Path] = []
    if installation_method is not None:
        linker_inputs.append(
            support.compile_installation_metadata(
                output_dir / "metadata",
                installation_method,
                version,
                arguments=_static_sdk_compile_arguments(selector),
                environment=env,
            )
        )

    if not skip_build:
        # Ensure checkouts exist before applying the Yams workaround. SwiftPM
        # will not overwrite an existing checkout during the subsequent build.
        support.run(["swift", "package", "resolve"], env=env)
        _patch_yams_for_static_sdk()
        _patch_tomlkit_for_static_sdk()

    products_directory = support.swift_build(
        configuration,
        product="swift-bundler",
        swift_sdk=selector,
        prebuilts=False,
        defines=["SWIFT_BUNDLER_METADATA"],
        linker_inputs=linker_inputs,
        environment=env,
        skip_build=skip_build and not linker_inputs,
    )
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
    binary = (
        support.swift_build(
            configuration,
            product="swift-bundler",
            environment=env,
        )
        / "swift-bundler"
    )
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


def _strip_linux_executable(binary: Path) -> None:
    """Strip debug information from the staged executable.

    Cross-compiled builds are left untouched.
    """
    if cross_compiling():
        return

    strip = support.require_command(
        "strip", "Install binutils (for example `apt install binutils`)."
    )
    before = binary.stat().st_size
    support.run([strip, "--strip-all", str(binary)])
    after = binary.stat().st_size
    logging.info(
        "Stripped %s (%.1f MB -> %.1f MB)",
        binary.name,
        before / 1_000_000,
        after / 1_000_000,
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
    _strip_linux_executable(main_executable)
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
    if not cross_compiling():
        logging.info(
            "Would strip the staged executable (debug information is removed)"
        )
    support.log_command(
        support.swift_build_arguments(
            configuration,
            product="swift-bundler",
            swift_sdk=static_sdk_selector(arch),
            prebuilts=False,
        )
    )
    support.log_command(
        support.swift_build_arguments(
            configuration,
            swift_sdk=static_sdk_selector(arch),
            show_bin_path=True,
        )
    )
    logging.info("Would stage %s for Linux %s in %s", version, arch, output_dir)
