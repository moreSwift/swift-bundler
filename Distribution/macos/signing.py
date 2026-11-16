"""Code signing helpers for macOS distribution builds."""

from __future__ import annotations

import os
from pathlib import Path

from common import support


def sign_binary(binary: Path) -> None:
    """Sign a Mach-O executable, ad-hoc when no identity is configured."""
    identity = os.environ.get("SBUN_APP_IDENTITY")
    arguments = ["codesign", "--force"]
    if identity:
        arguments += ["--options", "runtime", "--timestamp"]
    arguments += ["--sign", identity or "-", str(binary)]
    support.run(arguments)
