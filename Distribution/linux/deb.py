"""Build a Debian package from a staged Linux tree."""

from __future__ import annotations

import logging
import os
import shutil
import tempfile
from pathlib import Path
from typing import List

from common import support
from linux.staging import Stage

MAINTAINER = "moreSwift <contact@moreswift.dev>"
FALLBACK_DEPENDS = "libc6, libstdc++6, libgcc-s1, libcurl4, libxml2"


def _filter_bundled_dependencies(depends: str, stage: Stage) -> str:
    """Drop dependencies that are satisfied by libraries we bundle.

    dpkg-shlibdeps can map a bundled ICU soname back to the host's ``libicuNN``
    package even when the soname is in the private search directory. Bundling
    ICU is deliberate, so keep the package portable across distributions with
    different ICU package names.
    """
    bundled = {path.name for path in stage.library_directory.glob("*.so*")}
    bundles_icu = any(name.startswith("libicu") for name in bundled)
    if not bundles_icu:
        return depends

    clauses = [clause.strip() for clause in depends.split(",") if clause.strip()]
    filtered = [clause for clause in clauses if not clause.startswith("libicu")]
    return ", ".join(filtered)


def _compute_depends(stage: Stage, output_dir: Path) -> str:
    """Use dpkg-shlibdeps to derive versioned system dependencies."""
    shlibdeps = shutil.which("dpkg-shlibdeps")
    if shlibdeps is None:
        logging.warning(
            "dpkg-shlibdeps not found; falling back to a static Depends list"
        )
        return FALLBACK_DEPENDS

    with tempfile.TemporaryDirectory(
        prefix="swift-bundler-shlibdeps-", dir=str(output_dir)
    ) as temporary:
        work = Path(temporary)
        (work / "debian").mkdir()
        (work / "debian" / "control").write_text(
            """Source: swift-bundler
Section: devel
Priority: optional
Maintainer: {maintainer}
Standards-Version: 4.6.0
Homepage: https://swiftbundler.dev

Package: swift-bundler
Architecture: any
Description: A tool for creating apps from Swift packages
"""
            .format(maintainer=MAINTAINER),
            encoding="utf-8",
        )

        libraries = sorted(stage.library_directory.glob("*.so*"))
        command: List[str] = [
            shlibdeps,
            "-O",
            "--ignore-missing-info",
            f"-l{stage.library_directory}",
            str(stage.main_executable),
        ] + [str(library) for library in libraries]

        result = support.run(command, cwd=work, capture=True, check=False)
        if result.returncode != 0:
            logging.warning(
                "dpkg-shlibdeps failed; falling back to a static Depends list:\n%s",
                ((result.stdout or "") + (result.stderr or "")).strip(),
            )
            return FALLBACK_DEPENDS

        for line in (result.stdout or "").splitlines():
            line = line.strip()
            if line.startswith("shlibs:Depends="):
                depends = line[len("shlibs:Depends=") :].strip()
                return _filter_bundled_dependencies(
                    depends or FALLBACK_DEPENDS, stage
                )

    return FALLBACK_DEPENDS


def build_deb(
    stage: Stage,
    output_dir: Path,
    *,
    revision: str = "1",
    dry_run: bool = False,
) -> Path:
    if dry_run:
        logging.info(
            "[dry-run] would build a Debian package for %s-%s (%s)",
            stage.version,
            revision,
            stage.arch,
        )
        return output_dir / f"swift-bundler_{stage.version}-{revision}_{support.deb_arch(stage.arch)}.deb"

    support.require_command(
        "dpkg-deb",
        "Debian packages can only be built on a dpkg-based host.",
    )

    depends = _compute_depends(stage, output_dir)
    logging.info("Debian Depends: %s", depends)

    with tempfile.TemporaryDirectory(
        prefix="swift-bundler-deb-", dir=str(output_dir)
    ) as temporary:
        work = Path(temporary)
        package_root = work / "package"
        support.copy_tree(stage.root, package_root)

        doc_directory = package_root / "usr" / "share" / "doc" / "swift-bundler"
        support.ensure_directory(doc_directory)
        support.copy_file(
            support.REPO_ROOT / "Distribution" / "linux" / "deb" / "copyright",
            doc_directory / "copyright",
            mode=0o644,
        )

        control_directory = support.ensure_directory(package_root / "DEBIAN")
        template = (
            support.DISTRIBUTION_ROOT / "linux" / "deb" / "control.in"
        ).read_text(encoding="utf-8")
        control = support.render_template(
            template,
            {
                "VERSION": stage.version,
                "REVISION": revision,
                "ARCH": support.deb_arch(stage.arch),
                "MAINTAINER": MAINTAINER,
                "INSTALLED_SIZE": str(support.installed_size_kb(package_root)),
                "DEPENDS": depends,
            },
            source_name="linux/deb/control.in",
        )
        (control_directory / "control").write_text(control, encoding="utf-8")

        output = output_dir / (
            f"swift-bundler_{stage.version}-{revision}_"
            f"{support.deb_arch(stage.arch)}.deb"
        )
        support.remove_path(output)
        support.run(
            [
                "dpkg-deb",
                "--build",
                "--root-owner-group",
                "-Zxz",
                str(package_root),
                str(output),
            ]
        )

        support.run(["dpkg-deb", "--info", str(output)])
        support.run(["dpkg-deb", "--contents", str(output)], capture=True)

        logging.info("Created %s", output)
        return output


def print_plan(stage: Stage, output_dir: Path, revision: str = "1") -> None:
    logging.info(
        "Would run dpkg-shlibdeps and dpkg-deb for %s-%s (%s) in %s",
        stage.version,
        revision,
        stage.arch,
        output_dir,
    )
