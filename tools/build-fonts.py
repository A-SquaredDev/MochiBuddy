#!/usr/bin/env python3
"""Subset the app's fonts into tools/mochi-fonts.css as inline woff2.

    python3 -m pip install fonttools brotli
    python3 tools/build-fonts.py

The test plan page has to work with no network (and the artifact host blocks
external font URLs outright), so Fredoka and Nunito ride along base64'd,
subset to the characters the plan actually uses. Only needs re-running if
MochiBuddy/Fonts changes.
"""

from __future__ import annotations

import base64
import tempfile
from pathlib import Path

from fontTools import subset

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "tools" / "mochi-fonts.css"

# Latin plus the punctuation the plan leans on: arrows, middots, curly quotes.
UNICODES = (
    "U+0020-007E,U+00A0,U+00B7,U+00D7,U+2010-2014,"
    "U+2018-201D,U+2022,U+2026,U+2192,U+2713,U+00B0"
)

FACES = [
    ("Fredoka", ROOT / "MochiBuddy/Fonts/Fredoka-Variable.ttf", "300 700"),
    ("Nunito", ROOT / "MochiBuddy/Fonts/Nunito-Variable.ttf", "300 900"),
]


def main() -> None:
    css = []
    with tempfile.TemporaryDirectory() as tmp:
        for name, path, weights in FACES:
            dst = Path(tmp) / f"{name}.woff2"
            subset.main([
                str(path),
                f"--unicodes={UNICODES}",
                "--layout-features=kern,liga,calt",
                "--no-hinting",
                "--flavor=woff2",
                f"--output-file={dst}",
            ])
            payload = base64.b64encode(dst.read_bytes()).decode()
            css.append(
                f"@font-face{{font-family:'{name}';font-style:normal;"
                f"font-weight:{weights};font-display:swap;"
                f"src:url(data:font/woff2;base64,{payload}) format('woff2');}}"
            )
            print(f"{name}: {dst.stat().st_size // 1024} KB woff2")

    OUTPUT.write_text("\n".join(css) + "\n")
    print(f"wrote {OUTPUT.relative_to(ROOT)}: {OUTPUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
