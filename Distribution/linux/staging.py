"""Shared Linux build, dependency-discovery and staging logic."""

from __future__ import annotations

import json
import logging
import os
import re
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Sequence, Tuple

from common import support

# Copied from GenericLinuxBundler.dynamicLibraryBundlingAllowList. Keep this
# in sync with the bundler if Swift Bundler adds/removes runtime libraries.
DYNAMIC_LIBRARY_ALLOW_LIST = [
    "libswiftCore",
    "libswiftGlibc",
    "libswiftDispatch",
    "libswiftDistributed",
    "libswiftObservation",
    "libswiftRegexBuilder",
    "libswiftRemoteMirror",
    "libswiftSynchronization",
    "libswiftSwiftOnoneSupport",
    "libBlocksRuntime",
    "libdispatch",
    "libswift_Volatile",
    "libswift_Concurrency",
    "libswift_RegexParser",
    "libswift_StringProcessing",
    "libswift_Backtracing",
    "libswift_Builtin_float",
    "libswift_Differentiation",
    "lib_FoundationICU",
    "lib_InternalSwiftScan",
    "lib_InternalSwiftStaticMirror",
    "libFoundation",
    "libFoundationXML",
    "libFoundationEssentials",
    "libFoundationNetworking",
    "libFoundationInternationalization",
    "libicuuc",
    "libicudata",
    "libicuucswift",
    "libicui18nswift",
    "libicudataswift",
]

# Libraries that belong to the host system ABI and must never be redistributed.
SYSTEM_LIBRARY_BASES = {
    "linux-vdso",
    "linux-gate",
    "ld-linux",
    "ld-linux-x86-64",
    "ld-linux-aarch64",
    "libc",
    "libm",
    "libpthread",
    "libdl",
    "librt",
    "libgcc_s",
    "libstdc++",
    "libresolv",
    "libutil",
    "libnsl",
    "libanl",
    "libmvec",
}

_LDD_LINE = re.compile(
    r"^\s*(\S+)\s+=>\s+(\S+)\s+\(0x[0-9a-fA-F]+\)\s*$"
)
_LDD_NOT_FOUND = re.compile(r"^\s*(\S+)\s+=>\s+not found\s*$")


@dataclass
class Stage:
    root: Path
    main_executable: Path
    library_directory: Path
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
        "--disable-experimental-prebuilts",
    ]
    if not skip_build:
        support.run(build_command, env=env)

    output = support.command_stdout(
        build_command[:2]
        + ["--show-bin-path", "-c", configuration]
        + ["--disable-experimental-prebuilts"],
        env=env,
    )
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    if not lines:
        raise support.PackagingError("`swift build --show-bin-path` produced no output")
    products_directory = Path(lines[-1])
    binary = products_directory / "swift-bundler"
    support.require_file(binary, "built swift-bundler executable")

    version = support.command_stdout([binary, "--version"])
    logging.info("Built %s", version)
    return binary, products_directory


def runtime_library_paths() -> List[Path]:
    output = support.command_stdout(
        ["swiftc", "-print-target-info"],
        env=support.toolchain_environment(),
    )
    try:
        info = json.loads(output)
    except json.JSONDecodeError as error:
        raise support.PackagingError(
            f"Failed to parse `swiftc -print-target-info` output: {error}"
        ) from error

    paths = info.get("paths", {}).get("runtimeLibraryPaths", [])
    return [Path(path) for path in paths]


def _ldd_environment(products_directory: Path, runtime_paths: Sequence[Path]) -> dict:
    entries = [str(products_directory)]
    entries.extend(str(path) for path in runtime_paths)
    existing = os.environ.get("LD_LIBRARY_PATH")
    if existing:
        entries.append(existing)
    return {"LD_LIBRARY_PATH": os.pathsep.join(entries)}


def parse_ldd_output(output: str) -> Tuple[List[Tuple[str, Path]], List[str]]:
    """Parse ldd output into ``(soname, path)`` pairs and missing sonames."""
    dependencies: List[Tuple[str, Path]] = []
    missing: List[str] = []

    for line in output.splitlines():
        not_found = _LDD_NOT_FOUND.match(line)
        if not_found:
            missing.append(not_found.group(1))
            continue

        match = _LDD_LINE.match(line)
        if match is None:
            continue

        soname, path = match.groups()
        dependencies.append((soname, Path(path)))

    return dependencies, missing


def discover_linux_dependencies(
    binary: Path, products_directory: Path
) -> List[Tuple[str, Path]]:
    """Return ``(soname, resolved path)`` pairs to bundle."""
    runtime_paths = runtime_library_paths()
    env = _ldd_environment(products_directory, runtime_paths)

    result = support.run(["ldd", str(binary)], capture=True, env=env)
    output = result.stdout or ""
    logging.debug("ldd output for %s:\n%s", binary, output)

    found, missing = parse_ldd_output(output)
    dependencies: List[Tuple[str, Path]] = []
    seen = set()

    for soname, path in found:
        resolved = path.resolve()
        if not resolved.is_file():
            missing.append(soname)
            continue

        base = soname.split(".")[0]
        if base in SYSTEM_LIBRARY_BASES:
            logging.debug("Skipping system library %s", soname)
            continue

        should_bundle = base in DYNAMIC_LIBRARY_ALLOW_LIST or support.is_relative_to(
            resolved, products_directory
        )
        if not should_bundle:
            logging.debug("Skipping external library %s (%s)", soname, resolved)
            continue

        key = str(resolved)
        if key in seen:
            continue
        seen.add(key)
        dependencies.append((soname, resolved))

    if missing:
        raise support.PackagingError(
            "Failed to resolve dynamic dependencies: " + ", ".join(sorted(set(missing)))
        )

    return dependencies


def _patch_runpath(path: Path, runpath: str) -> None:
    support.run(["patchelf", str(path), "--set-rpath", runpath])


def _generate_completion(binary: Path, shell: str) -> str:
    result = support.run(
        [str(binary), "--generate-completion-script", shell], capture=True
    )
    return result.stdout or ""


def stage_linux_tree(
    binary: Path,
    products_directory: Path,
    output_dir: Path,
    version: str,
    arch: str,
) -> Stage:
    support.require_command(
        "patchelf",
        "Install it with your package manager (for example `apt install patchelf`).",
    )

    stage_root = output_dir / f"stage-{arch}"
    support.remove_path(stage_root)
    binary_directory = support.ensure_directory(stage_root / "usr" / "bin")
    library_directory = support.ensure_directory(
        stage_root / "usr" / "lib" / "swift-bundler"
    )
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

    # `sbun` is the short alias for `swift-bundler`.
    alias = binary_directory / "sbun"
    os.symlink("swift-bundler", alias)

    dependencies = discover_linux_dependencies(binary, products_directory)
    logging.info("Bundling %d dynamic librar%s", len(dependencies), "y" if len(dependencies) == 1 else "ies")
    for soname, source in dependencies:
        destination = library_directory / soname
        support.copy_file(source, destination, mode=0o644)
        _patch_runpath(destination, "$ORIGIN")

    _patch_runpath(
        main_executable,
        "$ORIGIN/../lib/swift-bundler:$ORIGIN/../lib64/swift-bundler",
    )

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
    for shell, (destination, alias_destination, mode) in completions.items():
        contents = _generate_completion(main_executable, shell)
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

    result = support.run(["ldd", str(main_executable)], capture=True)
    if "not found" in (result.stdout or ""):
        raise support.PackagingError(
            "Staged executable still has unresolved dependencies:\n"
            + (result.stdout or "")
        )
    support.run([str(main_executable), "--version"])

    return Stage(
        root=stage_root,
        main_executable=main_executable,
        library_directory=library_directory,
        version=version,
        arch=arch,
    )


def stage_linux_loose(stage: Stage, output_dir: Path) -> Tuple[Path, Path]:
    name = f"swift-bundler-{stage.version}-linux-{stage.arch}"
    root = output_dir / name
    support.remove_path(root)
    support.ensure_directory(root)

    support.copy_tree(stage.root / "usr" / "bin", root / "bin", symlinks=True)
    support.copy_tree(stage.root / "usr" / "lib", root / "lib", symlinks=True)
    support.copy_tree(stage.root / "usr" / "share", root / "share", symlinks=True)

    readme = f"""Swift Bundler {stage.version} (Linux {stage.arch})
====================================================

This is a self-contained Swift Bundler distribution. The binary needs the
libraries in `lib/swift-bundler`, so keep this directory together.

Run it directly:

    ./bin/swift-bundler --help
    ./bin/sbun --help

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
    support.log_command(
        [
            "swift",
            "build",
            "-c",
            configuration,
            "--product",
            "swift-bundler",
            "--disable-experimental-prebuilts",
        ]
    )
    support.log_command(
        ["swift", "build", "--show-bin-path", "-c", configuration]
    )
    support.log_command(["ldd", "<built swift-bundler>", "  # with LD_LIBRARY_PATH"])
    support.log_command(["patchelf", "<main>", "--set-rpath", "$ORIGIN/../lib/swift-bundler:$ORIGIN/../lib64/swift-bundler"])
    support.log_command(["patchelf", "<library>", "--set-rpath", "$ORIGIN"])
    logging.info("Would stage %s for Linux %s in %s", version, arch, output_dir)
