"""Build an RPM package from a staged Linux tree."""

from __future__ import annotations

import logging
import os
import platform
import shutil
import tempfile
from pathlib import Path

from common import support
from linux.staging import Stage

SUMMARY = "A tool for creating apps from Swift packages"
DESCRIPTION = (
    "Swift Bundler builds, bundles and runs Swift applications without "
    "requiring an Xcode project."
)

# Directories that Homebrew's rpm maps to its own prefix by default. The
# generated packages must use the FHS layout, so override every one of them.
CROSS_PREFIX_DEFINES = (
    ("_prefix", "/usr"),
    ("_exec_prefix", "/usr"),
    ("_bindir", "/usr/bin"),
    ("_sbindir", "/usr/sbin"),
    ("_libdir", "/usr/lib64"),
    ("_libexecdir", "/usr/libexec"),
    ("_datadir", "/usr/share"),
    ("_sysconfdir", "/etc"),
    ("_localstatedir", "/var"),
    ("_sharedstatedir", "/var/lib"),
    ("_infodir", "/usr/share/info"),
    ("_mandir", "/usr/share/man"),
    ("_docdir", "/usr/share/doc"),
    ("_defaultdocdir", "/usr/share/doc"),
)


def write_cross_rpmrc(
    rpmrc: Path,
    rpm_config_directory: Path,
    host_arch: str,
    target_arch: str,
) -> Path:
    """Write an `rpmrc` that lets a host `rpmbuild` target a Linux arch.

    Homebrew's rpm reports `compatible archs: <host> noarch`, so building for
    a foreign architecture fails with "No compatible architectures found for
    build". Nothing is actually compiled—the spec only copies staged files—so
    declaring the target architecture compatible is safe.
    """
    shutil.copyfile(rpm_config_directory / "rpmrc", rpmrc)
    os.chmod(rpmrc, 0o644)
    if host_arch != target_arch:
        with rpmrc.open("a", encoding="utf-8") as file:
            file.write(f"\nbuildarch_compat: {host_arch}: {target_arch} noarch\n")
    return rpmrc


def macos_cross_arguments(topdir: Path, target_arch: str) -> list:
    """Return the extra `rpmbuild` arguments needed to cross-build on macOS."""
    rpm_config_directory = Path(
        support.command_stdout(["rpm", "--eval", "%{_rpmconfigdir}"])
    )
    host_arch = support.command_stdout(["rpm", "--eval", "%{_build_arch}"])
    rpmrc = write_cross_rpmrc(
        topdir / "rpmrc", rpm_config_directory, host_arch, target_arch
    )
    arguments = ["--rcfile", str(rpmrc), "--target", f"{target_arch}-linux"]
    # RPM 6 requires the owning group of every packaged file, so a root-owned
    # package would gain an unsatisfiable `Requires: group(root)` on older
    # rpm-based distributions. Dilute it into a recommendation.
    arguments += ["--define", "_use_weak_usergroup_deps 1"]
    for name, value in CROSS_PREFIX_DEFINES:
        arguments += ["--define", f"{name} {value}"]
    return arguments


def build_rpm(
    stage: Stage,
    output_dir: Path,
    *,
    release: str = "1",
    dry_run: bool = False,
) -> Path:
    output = output_dir / (
        f"swift-bundler-{stage.version}-{release}."
        f"{support.rpm_arch(stage.arch)}.rpm"
    )
    if dry_run:
        logging.info("[dry-run] would build %s", output)
        return output

    support.require_command(
        "rpmbuild",
        "Install the RPM build tools (for example `apt install rpm` or "
        "`dnf install rpm-build`).",
    )

    topdir = Path(tempfile.mkdtemp(prefix="swift-bundler-rpm-"))
    try:
        for directory in ("SPECS", "SOURCES", "BUILD", "BUILDROOT", "RPMS", "SRPMS"):
            (topdir / directory).mkdir(parents=True, exist_ok=True)

        template = (
            support.DISTRIBUTION_ROOT / "linux" / "rpm" / "swift-bundler.spec.in"
        ).read_text(encoding="utf-8")
        spec = support.render_template(
            template,
            {
                "VERSION": stage.version,
                "RELEASE": release,
                "ARCH": support.rpm_arch(stage.arch),
                "SUMMARY": SUMMARY,
                "DESCRIPTION": DESCRIPTION,
            },
            source_name="linux/rpm/swift-bundler.spec.in",
        )
        spec_path = topdir / "SPECS" / "swift-bundler.spec"
        spec_path.write_text(spec, encoding="utf-8")

        command = [
            "rpmbuild",
            "--define",
            f"_topdir {topdir}",
            "--define",
            f"_stagedir {stage.root}",
        ]
        if platform.system() == "Darwin":
            command += macos_cross_arguments(
                topdir, support.rpm_arch(stage.arch)
            )
        command += ["-bb", str(spec_path)]

        support.run(command, cwd=topdir)

        rpm_files = sorted((topdir / "RPMS").rglob("*.rpm"))
        if not rpm_files:
            raise support.PackagingError(
                f"rpmbuild completed but no .rpm was found under {topdir / 'RPMS'}"
            )
        support.remove_path(output)
        support.copy_file(rpm_files[0], output)

        support.run(["rpm", "-qlp", str(output)])
        support.run(["rpm", "-qpR", str(output)], capture=True)
        logging.info("Created %s", output)
        return output
    finally:
        shutil.rmtree(topdir, ignore_errors=True)


def print_plan(stage: Stage, output_dir: Path, release: str = "1") -> None:
    logging.info(
        "Would run rpmbuild for %s-%s (%s) in %s",
        stage.version,
        release,
        stage.arch,
        output_dir,
    )
