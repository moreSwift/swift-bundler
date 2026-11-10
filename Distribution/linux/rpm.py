"""Build an RPM package from a staged Linux tree."""

from __future__ import annotations

import logging
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

        support.run(
            [
                "rpmbuild",
                "--define",
                f"_topdir {topdir}",
                "--define",
                f"_stagedir {stage.root}",
                "-bb",
                str(spec_path),
            ],
            cwd=topdir,
        )

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
