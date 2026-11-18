#!/usr/bin/env python3
"""Build the pitch document as a self-contained HTML and a PDF.

The markdown is the source of truth. This script only adds the cover and prints
the page; nothing in it is content.

    python3 pitches/build.py
"""

from __future__ import annotations

import base64
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "PITCHES.md"
CSS = ROOT / "pitches" / "pitch.css"
OUT_HTML = ROOT / "pitches" / "cauldron-slate.html"
OUT_PDF = ROOT / "pitches" / "cauldron-slate.pdf"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

COVER = [
    ("pitches/art/heavy-weather.png", "01 · Heavy Weather"),
    ("pitches/art/lowtide.png", "02 · Lowtide"),
    ("pitches/art/greenware.png", "03 · Greenware"),
]


def image_uri(relative: str) -> str:
    data = base64.b64encode((ROOT / relative).read_bytes()).decode("ascii")
    return f"data:image/png;base64,{data}"


def cover_html() -> str:
    figures = "\n".join(
        f'<figure><img src="{image_uri(path)}" alt="{caption}" />'
        f"<figcaption>{caption}</figcaption></figure>"
        for path, caption in COVER
    )
    return f"""
<section class="cover">
  <div>
    <p class="kicker">Cauldron Slate 01 · 2026</p>
    <h1 class="cover-title">Three games for the<br />Cauldron + BEAM stack</h1>
    <p class="cover-sub">A 3D mech duel where the storm is the third fighter.
    A co-op salvage world that lives on a tide. A stop-motion clay adventure
    about putting things back together.</p>
  </div>
  <div class="cover-art">
    {figures}
  </div>
  <div class="cover-foot">
    <span>Cauldron 2D / 3D / GPU · NxDiffusion Studio · Blender</span>
    <span>Pitches for a decision, not a plan with dates</span>
  </div>
</section>
"""


def build_html() -> str:
    pandoc = shutil.which("pandoc")
    if not pandoc:
        sys.exit("pandoc is not on PATH")

    result = subprocess.run(
        [
            pandoc,
            str(SOURCE),
            "-f", "markdown",
            "-t", "html5",
            "--embed-resources",
            "--standalone",
            "--css", str(CSS),
            "--metadata", "title=Cauldron Slate 01",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )

    html = result.stdout
    html = re.sub(r'<header id="title-block-header">.*?</header>\s*', "", html, flags=re.S)
    html = html.replace("<body>", "<body>\n" + cover_html(), 1)
    return html


def build_pdf(html_path: pathlib.Path) -> None:
    if not pathlib.Path(CHROME).exists():
        print("Chrome not found; HTML written, PDF skipped.", file=sys.stderr)
        return

    profile = pathlib.Path("/tmp/cauldron-pitch-chrome")
    subprocess.run(
        [
            CHROME,
            "--headless=new",
            "--disable-gpu",
            "--no-sandbox",
            f"--user-data-dir={profile}",
            "--no-pdf-header-footer",
            f"--print-to-pdf={OUT_PDF}",
            html_path.resolve().as_uri(),
        ],
        check=False,
        capture_output=True,
        text=True,
    )

    if not OUT_PDF.exists():
        print("PDF was not written.", file=sys.stderr)


def main() -> None:
    html = build_html()
    OUT_HTML.write_text(html)
    print(f"wrote {OUT_HTML.relative_to(ROOT)} ({OUT_HTML.stat().st_size / 1e6:.1f} MB)")

    build_pdf(OUT_HTML)
    if OUT_PDF.exists():
        print(f"wrote {OUT_PDF.relative_to(ROOT)} ({OUT_PDF.stat().st_size / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
