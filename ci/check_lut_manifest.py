#!/usr/bin/env python3
import json
import sys
from pathlib import Path


root = Path(sys.argv[1] if len(sys.argv) > 1 else "luts")
manifest_path = root / "manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
files = {path.relative_to(root).as_posix(): path for path in root.rglob("*.cube")}

if set(manifest) != set(files):
	missing = sorted(set(files) - set(manifest))
	stale = sorted(set(manifest) - set(files))
	raise SystemExit(f"manifest entries differ: missing={missing}, stale={stale}")

for relative, path in files.items():
	entry = manifest[relative]
	if entry.get("dim") not in (1, 3) or entry.get("size") != path.stat().st_size:
		raise SystemExit(f"manifest entry is invalid: {relative}")

print(f"LUT manifest matches {len(files)} files")
