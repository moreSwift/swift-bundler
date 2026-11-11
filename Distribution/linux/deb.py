"""Build a Debian package from a staged, statically linked Linux tree."""

from __future__ import annotations

import logging
import tempfile
from pathlib import Path

from common import support
from linux.staging import Stage

MAINTAINER = "moreSwift <contact@moreswift.dev>"


def build_deb(
    stage: Stage,
    output_dir: Path,
    *,
    revision: str = "1",
    dry_run: bool = False,
) -> Path:
    output = output_dir / (
        f"swift-bundler_{stage.version}-{revision}_"
        f"{support.deb_arch(stage.arch)}.deb"
    )
    if dry_run:
        logging.info("[dry-run] would build %s", output)
        return output

    support.require_command(
        "dpkg-deb",
        "Debian packages can only be built on a dpkg-based host.",
    )

    with tempfile.TemporaryDirectory(
        prefix="swift-bundler-deb-", dir=str(output_dir)
    ) as temporary:
        work = Path(temporary)
        package_root = work / "package"
        support.copy_tree(stage.root, package_root, symlinks=True)

        doc_directory = package_root / "usr" / "share" / "doc" / "swift-bundler"
        support.ensure_directory(doc_directory)
        support.copy_file(
            support.DISTRIBUTION_ROOT / "linux" / "deb" / "copyright",
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
            },
            source_name="linux/deb/control.in",
        )
        (control_directory / "control").write_text(control, encoding="utf-8")

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
        "Would build Debian package %s-%s (%s) in %s",
        stage.version,
        revision,
        stage.arch,
        output_dir,
    )
