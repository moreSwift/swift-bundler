"""Windows build, DLL discovery, and flat-directory staging."""

from __future__ import annotations

import json
import logging
import os
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Sequence, Set, Tuple

from common import support

# Copied from GenericWindowsBundler.dllBundlingAllowList. Keep this in sync
# with the bundler if Swift Bundler adds/removes runtime libraries.
DLL_ALLOW_LIST = {
    f"{name}.dll".lower()
    for name in [
        "swiftCore",
        "swiftCRT",
        "swiftDispatch",
        "swiftDistributed",
        "swiftObservation",
        "swiftRegexBuilder",
        "swiftRemoteMirror",
        "swiftSwiftOnoneSupport",
        "swiftSynchronization",
        "swiftWinSDK",
        "Foundation",
        "FoundationXML",
        "FoundationNetworking",
        "FoundationEssentials",
        "FoundationInternationalization",
        "BlocksRuntime",
        "_FoundationICU",
        "_InternalSwiftScan",
        "_InternalSwiftStaticMirror",
        "swift_Concurrency",
        "swift_RegexParser",
        "swift_StringProcessing",
        "swift_Differentiation",
        "concrt140",
        "msvcp140",
        "msvcp140d",
        "msvcp140_1",
        "msvcp140_2",
        "msvcp140_atomic_wait",
        "msvcp140_codecvt_ids",
        "vccorlib140",
        "vcruntime140",
        "vcruntime140d",
        "vcruntime140_1",
        "vcruntime140_1d",
        "ucrtbased",
        "vcruntime140_threads",
        "dispatch",
    ]
}

_API_SET_PREFIXES = ("api-", "ext-")


@dataclass
class Stage:
    root: Path
    main_executable: Path
    version: str
    arch: str


def build_swift_bundler(
    configuration: str = "release", skip_build: bool = False
) -> Tuple[Path, Path]:
    env = support.build_environment({"SBUN_NO_SCHEMA_GEN": "1"})
    build_command = [
        "swift",
        "build",
        "-c",
        configuration,
        "--product",
        "swift-bundler",
    ]
    if not skip_build:
        support.run(build_command, env=env)

    output = support.command_stdout(
        build_command[:2] + ["--show-bin-path", "-c", configuration],
        env=env,
    )
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    if not lines:
        raise support.PackagingError("`swift build --show-bin-path` produced no output")
    products_directory = Path(lines[-1])
    binary = products_directory / "swift-bundler.exe"
    support.require_file(binary, "built swift-bundler executable")

    version = support.command_stdout([str(binary), "--version"])
    logging.info("Built %s", version)
    return binary, products_directory


def runtime_library_paths() -> List[Path]:
    try:
        output = support.command_stdout(
            ["swiftc", "-print-target-info"],
            env=support.toolchain_environment(),
        )
        info = json.loads(output)
        return [
            Path(path)
            for path in info.get("paths", {}).get("runtimeLibraryPaths", [])
        ]
    except (support.PackagingError, json.JSONDecodeError) as error:
        logging.debug("Could not read Swift runtime library paths: %s", error)
        return []


def require_dumpbin() -> str:
    dumpbin = shutil.which("dumpbin")
    if dumpbin is None:
        raise support.PackagingError(
            "Required command not found: dumpbin\n"
            "Run this script from a Developer PowerShell for Visual Studio "
            "(or any environment where dumpbin is on PATH)."
        )
    return dumpbin


def parse_dumpbin_output(output: str) -> List[str]:
    lines = output.splitlines()
    heading = "Image has the following dependencies:"
    for index, line in enumerate(lines):
        if heading not in line:
            continue

        index += 1
        while index < len(lines) and not lines[index].strip():
            index += 1

        dependencies: List[str] = []
        while index < len(lines) and lines[index].strip():
            dependencies.append(lines[index].strip())
            index += 1
        return dependencies

    raise support.PackagingError(
        "Failed to parse dumpbin output: missing dependency section"
    )


def get_dll_dependencies(module: Path) -> List[str]:
    dumpbin = require_dumpbin()
    result = support.run([dumpbin, "/DEPENDENTS", str(module)], capture=True)
    try:
        return parse_dumpbin_output(result.stdout or "")
    except support.PackagingError as error:
        raise support.PackagingError(f"{error} (while inspecting {module})") from error


def _path_entries(runtime_paths: Sequence[Path]) -> List[Path]:
    # Prefer the Swift toolchain's own runtime paths over whatever happens to
    # be earlier on PATH, so we bundle the runtime matching the compiler.
    entries = list(runtime_paths)
    for entry in os.environ.get("PATH", "").split(os.pathsep):
        if entry:
            entries.append(Path(entry))
    return entries


def resolve_dll(
    name: str,
    products_directory: Path,
    runtime_paths: Sequence[Path],
) -> Optional[Path]:
    if name.lower().startswith(_API_SET_PREFIXES):
        return None

    candidate = products_directory / name
    if candidate.is_file():
        return candidate

    for directory in _path_entries(runtime_paths):
        candidate = directory / name
        if candidate.is_file():
            return candidate

    return None


def copy_windows_dependencies(
    module: Path,
    stage_root: Path,
    products_directory: Path,
    runtime_paths: Sequence[Path],
    visited: Optional[Set[str]] = None,
) -> None:
    visited = visited if visited is not None else set()

    for name in get_dll_dependencies(module):
        key = name.lower()
        if key in visited:
            continue

        source = resolve_dll(name, products_directory, runtime_paths)
        if source is None:
            logging.debug("Ignoring unresolved system DLL %s", name)
            continue

        is_product = support.is_relative_to(source, products_directory)
        if not is_product and key not in DLL_ALLOW_LIST:
            logging.debug("Ignoring non-allow-listed DLL %s (%s)", name, source)
            continue

        visited.add(key)
        destination = stage_root / source.name
        logging.info("Bundling %s", source.name)
        support.copy_file(source, destination)

        copy_windows_dependencies(
            source,
            stage_root,
            products_directory,
            runtime_paths,
            visited,
        )


def build_stage(
    version: str,
    arch: str,
    output_dir: Path,
    *,
    configuration: str = "release",
    skip_build: bool = False,
) -> Stage:
    binary, products_directory = build_swift_bundler(
        configuration=configuration, skip_build=skip_build
    )
    runtime_paths = runtime_library_paths()

    stage_root = output_dir / f"stage-{arch}"
    support.remove_path(stage_root)
    support.ensure_directory(stage_root)

    main_executable = stage_root / "swift-bundler.exe"
    support.copy_file(binary, main_executable)

    copy_windows_dependencies(
        binary,
        stage_root,
        products_directory,
        runtime_paths,
    )

    for name in ("LICENSE", "README.md"):
        support.copy_file(
            support.REPO_ROOT / name,
            stage_root / name,
            mode=0o644,
        )
    support.copy_file(
        support.DISTRIBUTION_ROOT / "windows" / "THIRD_PARTY_NOTICES.txt",
        stage_root / "THIRD_PARTY_NOTICES.txt",
        mode=0o644,
    )

    support.run([str(main_executable), "--version"])
    return Stage(
        root=stage_root,
        main_executable=main_executable,
        version=version,
        arch=arch,
    )


def print_plan(
    version: str,
    arch: str,
    output_dir: Path,
    *,
    configuration: str = "release",
) -> None:
    logging.info("+ $env:SBUN_NO_SCHEMA_GEN=1")
    support.log_command(
        [
            "swift",
            "build",
            "-c",
            configuration,
            "--product",
            "swift-bundler",
        ]
    )
    support.log_command(
        ["swift", "build", "--show-bin-path", "-c", configuration]
    )
    support.log_command(["dumpbin", "/DEPENDENTS", "<swift-bundler.exe>"])
    logging.info("Would stage %s for Windows %s in %s", version, arch, output_dir)
