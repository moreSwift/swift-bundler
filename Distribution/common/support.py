"""Shared helpers for the Swift Bundler distribution scripts.

The distribution scripts deliberately use only the Python standard library so that
they can run on a bare macOS, Linux, or Windows build host. Native packaging tools
(WiX, dpkg-deb, rpmbuild, pkgbuild, ...) are invoked with subprocess argument lists
rather than shell strings.
"""

from __future__ import annotations

import hashlib
import logging
import os
import platform
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import zipfile
from pathlib import Path, PurePosixPath
from typing import Dict, Iterable, List, Mapping, Optional, Sequence, Tuple

DISTRIBUTION_ROOT = Path(__file__).resolve().parent.parent
REPO_ROOT = DISTRIBUTION_ROOT.parent
SWIFT_BUNDLER_VERSION_FILE = REPO_ROOT / "Sources" / "SwiftBundler" / "SwiftBundler.swift"

_NUMERIC_VERSION = re.compile(r"^\d+\.\d+\.\d+$")
_VERSION_DECLARATION = re.compile(
    r"_version\s*=\s*Version\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)"
)

_HOST_ARCH_ALIASES = {
    "x86_64": "x86_64",
    "amd64": "x86_64",
    "x64": "x86_64",
    "arm64": "arm64",
    "aarch64": "arm64",
}


class PackagingError(Exception):
    """An expected packaging failure with a message suitable for the user."""


def setup_logging(verbose: bool = False) -> None:
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(message)s",
    )


def log_command(arguments: Sequence[str]) -> None:
    logging.info("+ %s", " ".join(shlex.quote(str(argument)) for argument in arguments))


def run(
    arguments: Sequence[object],
    *,
    cwd: Optional[Path] = None,
    env: Optional[Mapping[str, str]] = None,
    dry_run: bool = False,
    check: bool = True,
    capture: bool = False,
) -> subprocess.CompletedProcess:
    """Run a command with an argument list (never through a shell)."""
    command = [str(argument) for argument in arguments]
    log_command(command)

    if dry_run:
        return subprocess.CompletedProcess(command, 0, "", "")

    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)

    try:
        result = subprocess.run(
            command,
            cwd=str(cwd) if cwd is not None else None,
            env=merged_env,
            text=True,
            errors="replace",
            capture_output=capture,
            check=False,
        )
    except FileNotFoundError as error:
        raise PackagingError(
            f"Required command not found: {command[0]}. "
            "Make sure it is installed and on PATH."
        ) from error

    if check and result.returncode != 0:
        detail = ""
        if capture:
            output = ((result.stdout or "") + (result.stderr or "")).strip()
            if output:
                detail = "\n" + output[:4000]
        raise PackagingError(
            f"Command failed with exit code {result.returncode}: "
            f"{' '.join(command)}{detail}"
        )

    return result


def toolchain_environment() -> Dict[str, str]:
    """Return environment overrides for an explicitly selected Swift toolchain.

    ``SBUN_TOOLCHAIN_BIN`` is a ``PATH``-style list of directories to prepend
    when locating ``swift``/``swiftc``. It is useful on machines with multiple
    toolchains installed (and for reproducible distribution builds).
    """
    extra = os.environ.get("SBUN_TOOLCHAIN_BIN")
    if not extra:
        return {}
    existing = os.environ.get("PATH", "")
    return {"PATH": extra + (os.pathsep + existing if existing else "")}


def build_environment(extra: Optional[Mapping[str, str]] = None) -> Dict[str, str]:
    environment = toolchain_environment()
    if extra:
        environment.update(extra)
    return environment


def require_command(name: str, hint: Optional[str] = None) -> str:
    path = shutil.which(name)
    if path is None:
        message = f"Required command not found: {name}"
        if hint:
            message += f"\n{hint}"
        raise PackagingError(message)
    return path


def command_stdout(arguments: Sequence[object], **kwargs) -> str:
    result = run(arguments, capture=True, **kwargs)
    return (result.stdout or "").strip()


def resolve_output_dir(value: Optional[str], platform_name: str) -> Path:
    """Return the platform-specific output directory (created if needed)."""
    if value:
        base = Path(value).expanduser().resolve()
    else:
        base = DISTRIBUTION_ROOT / "out"
    path = base / platform_name
    path.mkdir(parents=True, exist_ok=True)
    return path


def parse_version_from_source(path: Path = SWIFT_BUNDLER_VERSION_FILE) -> str:
    if not path.exists():
        raise PackagingError(f"Could not find Swift Bundler's version in {path}")
    contents = path.read_text(encoding="utf-8")
    match = _VERSION_DECLARATION.search(contents)
    if match is None:
        raise PackagingError(
            f"Failed to parse `_version = Version(x, y, z)` from {path}"
        )
    return ".".join(match.groups())


def resolve_version(cli_value: Optional[str] = None) -> str:
    version = cli_value or os.environ.get("SBUN_VERSION")
    if version is None:
        version = parse_version_from_source()
    if not _NUMERIC_VERSION.match(version):
        raise PackagingError(
            f"Invalid version '{version}'; expected a numeric MAJOR.MINOR.PATCH "
            "version (MSI cannot represent pre-release metadata)."
        )
    return version


def host_arch() -> str:
    machine = platform.machine().lower()
    arch = _HOST_ARCH_ALIASES.get(machine)
    if arch is None:
        raise PackagingError(f"Unsupported host architecture: {machine}")
    return arch


def resolve_arch(cli_value: Optional[str] = None) -> str:
    value = (cli_value or host_arch()).lower()
    arch = _HOST_ARCH_ALIASES.get(value)
    if arch is None:
        raise PackagingError(
            f"Unsupported architecture '{value}'; expected x86_64, amd64, arm64, "
            "or aarch64."
        )
    return arch


def deb_arch(arch: str) -> str:
    return {"x86_64": "amd64", "arm64": "arm64"}[arch]


def rpm_arch(arch: str) -> str:
    return {"x86_64": "x86_64", "arm64": "aarch64"}[arch]


def wix_arch(arch: str) -> str:
    return {"x86_64": "x64", "arm64": "arm64"}[arch]


def require_file(path: Path, description: Optional[str] = None) -> Path:
    if not path.is_file():
        raise PackagingError(f"Missing {description or 'required file'}: {path}")
    return path


def require_directory(path: Path, description: Optional[str] = None) -> Path:
    if not path.is_dir():
        raise PackagingError(f"Missing {description or 'required directory'}: {path}")
    return path


def ensure_directory(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def remove_path(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def copy_file(source: Path, destination: Path, mode: Optional[int] = None) -> None:
    ensure_directory(destination.parent)
    shutil.copy2(source, destination)
    if mode is not None:
        os.chmod(destination, mode)


def copy_tree(source: Path, destination: Path, *, symlinks: bool = False) -> None:
    shutil.copytree(
        source,
        destination,
        dirs_exist_ok=True,
        symlinks=symlinks,
    )


def is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def rename_completion_script(
    script: str, from_command: str, to_command: str
) -> str:
    """Produce a completion script for an alias of a command.

    ``swift-argument-parser`` hardcodes the command name in the generated
    completion script. Replacing it (including the generated function names)
    yields a valid script for the ``sbun`` alias.
    """
    return script.replace(from_command, to_command)


def render_template(
    template: str, replacements: Mapping[str, str], *, source_name: str = "template"
) -> str:
    """Replace ``@@TOKEN@@`` placeholders without interpreting shell/RPM syntax."""
    rendered = template
    for key, value in replacements.items():
        rendered = rendered.replace(f"@@{key}@@", value)

    unresolved = sorted(set(re.findall(r"@@[A-Z0-9_]+@@", rendered)))
    if unresolved:
        raise PackagingError(
            f"Unrendered placeholder(s) in {source_name}: {', '.join(unresolved)}"
        )
    return rendered


def render_template_file(
    path: Path, replacements: Mapping[str, str], destination: Path
) -> None:
    contents = path.read_text(encoding="utf-8")
    rendered = render_template(contents, replacements, source_name=str(path))
    ensure_directory(destination.parent)
    destination.write_text(rendered, encoding="utf-8")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_checksum(path: Path, checksum_path: Optional[Path] = None) -> Path:
    checksum_path = checksum_path or path.with_name(path.name + ".sha256")
    checksum_path.write_text(
        f"{sha256_file(path)}  {path.name}\n", encoding="utf-8"
    )
    return checksum_path


def installed_size_kb(root: Path) -> int:
    total = 0
    for path in root.rglob("*"):
        # Don't count symlink targets twice (for example the `sbun` alias).
        if path.is_symlink():
            continue
        if path.is_file():
            total += path.stat().st_size
    return max(1, (total + 1023) // 1024)


def zip_directory(
    source: Path,
    archive: Path,
    *,
    root_name: Optional[str] = None,
    dry_run: bool = False,
) -> None:
    if dry_run:
        logging.info("[dry-run] zip %s -> %s", source, archive)
        return

    ensure_directory(archive.parent)
    with zipfile.ZipFile(
        archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
    ) as zip_file:
        for path in sorted(source.rglob("*")):
            if path.is_dir():
                continue
            relative = PurePosixPath(*path.relative_to(source).parts)
            arcname = (
                PurePosixPath(root_name) / relative if root_name else relative
            )
            zip_file.write(path, arcname=str(arcname))


def tar_directory(
    source: Path,
    archive: Path,
    *,
    root_name: Optional[str] = None,
    dry_run: bool = False,
) -> None:
    if dry_run:
        logging.info("[dry-run] tar %s -> %s", source, archive)
        return

    ensure_directory(archive.parent)
    with tarfile.open(archive, "w:gz") as tar_file:
        tar_file.add(source, arcname=root_name or source.name)


def relative_to_repo(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


def cli_entry(main) -> int:
    """Run a CLI main function, converting expected errors to exit status 1."""
    try:
        return int(main() or 0)
    except PackagingError as error:
        logging.error("error: %s", error)
        return 1
    except KeyboardInterrupt:
        logging.error("interrupted")
        return 130


def python_version_at_least(major: int, minor: int) -> bool:
    return sys.version_info >= (major, minor)
