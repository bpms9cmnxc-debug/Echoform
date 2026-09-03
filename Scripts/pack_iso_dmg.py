#!/usr/bin/env python3
"""Pack the Echoform tree into an ISO 9660 image named .dmg (macOS mounts it)."""
from __future__ import annotations

import os
import sys
from pathlib import Path

from pycdlib import PyCdlib

ROOT = Path(__file__).resolve().parents[1]
OUT = Path("/tmp/Echoform-0.3.0.dmg")
COPY_TO = ROOT / "dist" / "Echoform-0.3.0.dmg"
SKIP_DIR = {".git", "dist", "build", "node_modules"}
SKIP_FILE = {".DS_Store"}


def iso9660_dir(n: int) -> str:
    return f"/D{n:05d}"


def iso9660_file(n: int) -> str:
    return f"/F{n:05d}.;1"


def main() -> int:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    iso = PyCdlib()
    iso.new(interchange_level=3, joliet=3, rock_ridge="1.09", vol_ident="ECHOFORM")

    dir_ids: dict[str, str] = {"": ""}
    next_d = 1
    next_f = 1

    def iso_parent(rel_dir: str) -> str:
        return dir_ids[rel_dir] if rel_dir else ""

    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIR)
        rel_dir = os.path.relpath(dirpath, ROOT)
        if rel_dir == ".":
            rel_dir = ""
        if rel_dir and rel_dir not in dir_ids:
            parent_rel = str(Path(rel_dir).parent)
            if parent_rel == ".":
                parent_rel = ""
            parent_iso = iso_parent(parent_rel)
            name = Path(rel_dir).name
            ident = iso9660_dir(next_d)
            next_d += 1
            iso_path = f"{parent_iso}{ident}" if parent_iso else ident
            joliet = "/" + rel_dir.replace("\\", "/")
            iso.add_directory(iso_path, rr_name=name, joliet_path=joliet)
            dir_ids[rel_dir] = iso_path
        parent_iso = iso_parent(rel_dir)
        joliet_dir = "/" + rel_dir.replace("\\", "/") if rel_dir else ""
        for name in sorted(filenames):
            if name in SKIP_FILE:
                continue
            src = Path(dirpath) / name
            if src.resolve() == OUT.resolve():
                continue
            ident = iso9660_file(next_f)
            next_f += 1
            iso_path = f"{parent_iso}{ident}" if parent_iso else ident
            joliet = f"{joliet_dir}/{name}" if joliet_dir else f"/{name}"
            iso.add_file(str(src), iso_path, rr_name=name, joliet_path=joliet)

    iso.write(str(OUT))
    iso.close()
    COPY_TO.parent.mkdir(parents=True, exist_ok=True)
    COPY_TO.write_bytes(OUT.read_bytes())
    print(f"Wrote {OUT} and {COPY_TO} ({OUT.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
