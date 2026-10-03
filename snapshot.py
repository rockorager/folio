#!/usr/bin/env python3
"""Snapshot the local Storybook catalog with Ourokit's module loader."""
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent
toolkit = Path(os.environ.get("OUROKIT_DIR", root.parent / "ourokit"))
subprocess.run([str(toolkit / "zig-out/bin/ouroctl"), "storybook", "snapshot",
                str(root / "stories.lua"), *sys.argv[1:]], check=True)
