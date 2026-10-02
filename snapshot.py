#!/usr/bin/env python3
"""Bundle local modules for Ourokit's isolated Storybook VM, then snapshot."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent
toolkit = Path(os.environ.get("OUROKIT_DIR", root.parent / "ourokit"))
source = """local builtin_require = require
local modules, loaded = {}, {}
local function require(name)
  if loaded[name] then return loaded[name] end
  if not modules[name] then return builtin_require(name) end
  loaded[name] = modules[name]()
  return loaded[name]
end
"""
for name in ("document", "commands", "view"):
    source += f"modules['{name}'] = function()\n" + (root / f"{name}.lua").read_text() + "\nend\n"
source += (root / "stories.lua").read_text()
with tempfile.TemporaryDirectory(prefix="folio-stories-") as directory:
    catalog = Path(directory) / "catalog.lua"
    catalog.write_text(source)
    subprocess.run([str(toolkit / "zig-out/bin/ouroctl"), "storybook", "snapshot",
                    str(catalog), *sys.argv[1:]], check=True)
