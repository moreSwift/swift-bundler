"""Build the loose Linux distribution archive."""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Tuple

from linux.staging import Stage, stage_linux_loose


def build_loose(stage: Stage, output_dir: Path, *, dry_run: bool = False) -> Tuple[Path, Path]:
    if dry_run:
        name = f"swift-bundler-{stage.version}-linux-{stage.arch}"
        logging.info("[dry-run] would create %s and %s.tar.gz", name, name)
        return output_dir / name, output_dir / f"{name}.tar.gz"

    root, archive = stage_linux_loose(stage, output_dir)
    logging.info("Created %s", root)
    logging.info("Created %s", archive)
    return root, archive
