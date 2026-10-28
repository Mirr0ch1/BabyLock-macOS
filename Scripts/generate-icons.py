#!/usr/bin/env python3
"""Regenerate the macOS app icon from the SVG source.

Requires: python3 -m pip install cairosvg

Usage:  python3 Scripts/generate-icons.py
"""

from __future__ import annotations

import struct
from pathlib import Path

import cairosvg

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets" / "icon" / "babylock-icon.svg"
ICON_DIR = ROOT / "assets" / "icon"
ICNS_PATH = ROOT / "BabyLock" / "Resources" / "AppIcon.icns"

# ICNS entry type -> pixel size. Modern macOS reads the large PNG entries;
# the smaller legacy entries keep Finder and old tools happy.
ENTRIES = {
    "icp4": 16,
    "icp5": 32,
    "icp6": 64,
    "ic07": 128,
    "ic08": 256,
    "ic09": 512,
    "ic10": 1024,
    "ic11": 32,
    "ic12": 64,
    "ic13": 256,
    "ic14": 512,
}


def render(size: int) -> bytes:
    return cairosvg.svg2png(
        url=str(SOURCE),
        output_width=size,
        output_height=size,
    )


def main() -> None:
    ICON_DIR.mkdir(parents=True, exist_ok=True)

    # Preview image used by the README.
    (ICON_DIR / "babylock-icon-1024.png").write_bytes(render(1024))

    chunks = bytearray(b"icns\x00\x00\x00\x00")
    for entry_type, size in ENTRIES.items():
        png = render(size)
        chunks += entry_type.encode("ascii")
        chunks += struct.pack(">I", len(png) + 8)
        chunks += png

    chunks[4:8] = struct.pack(">I", len(chunks))
    ICNS_PATH.write_bytes(chunks)
    print(f"Wrote {ICNS_PATH} ({len(chunks):,} bytes)")


if __name__ == "__main__":
    main()
