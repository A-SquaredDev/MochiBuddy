#!/usr/bin/env python3
"""Shared furniture for the QA pages in tools/.

The test plan page and the bug log page are meant to read as one pair of
tools, so the palette, type, buttons, and fields live here rather than being
copied twice. Colors come straight off MochiShared/MochiTheme.swift: Ube for
the light theme, Black Sesame for the dark one.
"""

from __future__ import annotations

import html
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / "tools" / "mochi-fonts.css"


def fonts_css() -> str:
    """Inlined Fredoka + Nunito, or nothing if build-fonts.py has not run."""
    return FONTS.read_text() if FONTS.exists() else ""


def inline(text: str) -> str:
    """The inline markdown these docs actually use."""
    out = html.escape(text.strip())
    out = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', out)
    out = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", out, flags=re.S)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\[(needs [^\]]+)\]", r'<span class="chip">\1</span>', out, flags=re.I)
    return out


def write(path: Path, page: str) -> None:
    """Entity-escape above ASCII so the page renders the same served, opened
    from disk, or mailed to someone."""
    path.write_bytes(page.encode("ascii", "xmlcharrefreplace"))


BASE_CSS = """
:root{
  color-scheme: light;
  /* Ube flavor, straight off MochiTheme.swift */
  --bg:#F5F1FC; --surface:#FFFFFF; --surface2:#FAF7FE;
  --ink:#382A4D; --muted:#786A93; --line:#E7DEF6;
  --accent:#7B4BC4; --accent-text:#7340BE; --accent-soft:#E7DBFA;
  --on-accent:#FFFFFF;
  --pass:#3B7827; --pass-soft:#E5F2D7;
  --fail:#B0301F; --fail-soft:#FADEDA;
  --blocked:#8A5300; --blocked-soft:#FFEAC8;
  --shadow:0 1px 2px rgba(56,42,77,.06), 0 8px 24px rgba(56,42,77,.06);
  --radius:18px;
}
@media (prefers-color-scheme: dark){
  :root{
    color-scheme: dark;
    /* Black Sesame */
    --bg:#211E2A; --surface:#2E2A38; --surface2:#353040;
    --ink:#F3EEF7; --muted:#A79FB5; --line:#413A50;
    --accent:#C9A6FF; --accent-text:#C9A6FF; --accent-soft:#453A58;
    --on-accent:#241A33;
    --pass:#9FD37E; --pass-soft:#31402A;
    --fail:#FF9DA6; --fail-soft:#4E2B31;
    --blocked:#FFC777; --blocked-soft:#4A3A1E;
    --shadow:0 1px 2px rgba(0,0,0,.32), 0 10px 28px rgba(0,0,0,.28);
  }
}
:root[data-theme="dark"]{
  color-scheme: dark;
  --bg:#211E2A; --surface:#2E2A38; --surface2:#353040;
  --ink:#F3EEF7; --muted:#A79FB5; --line:#413A50;
  --accent:#C9A6FF; --accent-text:#C9A6FF; --accent-soft:#453A58;
  --on-accent:#241A33;
  --pass:#9FD37E; --pass-soft:#31402A;
  --fail:#FF9DA6; --fail-soft:#4E2B31;
  --blocked:#FFC777; --blocked-soft:#4A3A1E;
  --shadow:0 1px 2px rgba(0,0,0,.32), 0 10px 28px rgba(0,0,0,.28);
}
:root[data-theme="light"]{
  color-scheme: light;
  --bg:#F5F1FC; --surface:#FFFFFF; --surface2:#FAF7FE;
  --ink:#382A4D; --muted:#786A93; --line:#E7DEF6;
  --accent:#7B4BC4; --accent-text:#7340BE; --accent-soft:#E7DBFA;
  --on-accent:#FFFFFF;
  --pass:#3B7827; --pass-soft:#E5F2D7;
  --fail:#B0301F; --fail-soft:#FADEDA;
  --blocked:#8A5300; --blocked-soft:#FFEAC8;
  --shadow:0 1px 2px rgba(56,42,77,.06), 0 8px 24px rgba(56,42,77,.06);
}

*{box-sizing:border-box}
[hidden]{display:none !important}
body{
  margin:0; background:var(--bg); color:var(--ink);
  font-family:Nunito, ui-rounded, -apple-system, system-ui, sans-serif;
  font-size:16px; line-height:1.5; font-weight:500;
  -webkit-text-size-adjust:100%;
}
strong{font-weight:800}
h1,h2,h3{font-family:Fredoka, ui-rounded, -apple-system, system-ui, sans-serif;
  font-weight:600; text-wrap:balance; margin:0}
a{color:var(--accent-text); text-underline-offset:3px}
code{font-family:ui-monospace, SFMono-Regular, Menlo, monospace; font-size:.88em}
button, textarea, input, select{font:inherit; color:inherit}
button{cursor:pointer}
:focus-visible{outline:2px solid var(--accent); outline-offset:2px; border-radius:8px}

.wrap{max-width:46rem; margin:0 auto; padding:0 16px 96px}

.chip{
  display:inline-block; font-size:11px; font-weight:800; letter-spacing:.05em; text-transform:uppercase;
  background:var(--accent-soft); color:var(--accent-text); border-radius:6px; padding:1px 6px;
  vertical-align:1px; white-space:nowrap;
}

.btn{
  border:1px solid var(--line); background:var(--surface2); border-radius:10px;
  padding:8px 14px; font-size:14px; font-weight:700; color:var(--ink);
  text-decoration:none; display:inline-flex; align-items:center;
}
.btn.primary{background:var(--accent); border-color:var(--accent); color:var(--on-accent)}
.btn.danger[data-armed="1"]{border-color:var(--fail); color:var(--fail); background:var(--fail-soft)}
.btn:disabled{opacity:.45; cursor:default}

.field{display:flex; flex-direction:column; gap:4px; flex:1 1 150px; min-width:0}
.field label{font-size:11px; font-weight:800; letter-spacing:.09em; text-transform:uppercase; color:var(--muted)}
.field input, .field select, .field textarea{
  background:var(--surface2); border:1px solid var(--line); border-radius:10px;
  padding:7px 10px; font-size:15px; font-weight:600; min-width:0; width:100%;
}
.field textarea{font-weight:500; resize:vertical; min-height:64px; line-height:1.45}

.filters{display:flex; gap:6px; overflow-x:auto; scrollbar-width:none; padding-bottom:1px}
.filters::-webkit-scrollbar{display:none}
.filters button{
  flex:none; border:1px solid var(--line); background:var(--surface); color:var(--muted);
  border-radius:999px; padding:4px 11px; font-size:13px; font-weight:700;
}
.filters button[aria-pressed="true"]{background:var(--accent); border-color:var(--accent); color:var(--on-accent)}

.seg{display:flex; gap:4px; flex-wrap:wrap}
.seg button{
  border:1px solid var(--line); background:var(--surface2); border-radius:9px;
  padding:5px 11px; font-size:13px; font-weight:700; color:var(--muted);
}
.seg button[aria-pressed="true"]{background:var(--accent); border-color:var(--accent); color:var(--on-accent)}

.warn-banner{
  margin:12px 0 0; padding:10px 12px; border-radius:12px; font-size:13px; font-weight:700;
  background:var(--blocked-soft); color:var(--blocked);
  border:1px solid color-mix(in srgb, var(--blocked) 30%, transparent);
}

.sheet{
  position:fixed; inset:0; z-index:40; display:none; place-items:center; padding:16px;
  background:color-mix(in srgb, var(--ink) 46%, transparent);
}
.sheet[open]{display:grid}
.sheet-card{
  background:var(--surface); border:1px solid var(--line); border-radius:var(--radius);
  box-shadow:var(--shadow); width:min(46rem, 100%); max-height:86vh; display:flex; flex-direction:column;
  padding:16px; gap:12px;
}
.sheet-card h3{font-size:18px}
.sheet-card p{margin:0; color:var(--muted); font-size:13.5px}
.sheet-card textarea{
  flex:1; min-height:44vh; width:100%; border:1px solid var(--line); border-radius:12px;
  background:var(--surface2); padding:12px; font-family:ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size:12.5px; line-height:1.55; white-space:pre; resize:none;
}
.sheet-actions{display:flex; gap:8px; flex-wrap:wrap}

.foot{margin-top:44px; padding-top:16px; border-top:1px solid var(--line); color:var(--muted); font-size:13px}

@media (prefers-reduced-motion: reduce){
  *{transition:none !important; animation:none !important}
}
"""
