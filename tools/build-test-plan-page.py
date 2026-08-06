#!/usr/bin/env python3
"""Turn manual-test-plan.md into a tappable checklist page.

    python3 tools/build-test-plan-page.py

Reads manual-test-plan.md (the source of truth - edit that, never the HTML)
and writes tools/manual-test-plan.html: the same plan with real checkboxes,
a note field on every item, per-section progress, and an export that hands
the results back as markdown.

Fonts come from tools/mochi-fonts.css (Fredoka + Nunito, subset to woff2 and
base64'd so the page needs no network). Regenerate that file with
tools/build-fonts.py if the app's fonts ever change.
"""

from __future__ import annotations

import argparse
import hashlib
import html
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mochi_page import BASE_CSS, ROOT, fonts_css, inline, write  # noqa: E402

SOURCE = ROOT / "manual-test-plan.md"
OUTPUT = ROOT / "tools" / "manual-test-plan.html"


# ---------------------------------------------------------------- parsing


def unwrap(lines: list[str]) -> str:
    return " ".join(line.strip() for line in lines if line.strip())


def parse(md: str) -> dict:
    lines = md.split("\n")
    doc: dict = {"title": "", "intro": [], "sections": []}
    section = None
    item = None
    sub = None
    buffer: list[str] = []
    in_intro = True

    def flush_intro():
        if buffer and in_intro:
            doc["intro"].append(unwrap(buffer))
        buffer.clear()

    def close_item():
        nonlocal item, sub
        if item is not None:
            item["text"] = unwrap(item["_text"])
            for s in item["subs"]:
                s["text"] = unwrap(s["_text"])
            del item["_text"]
            for s in item["subs"]:
                del s["_text"]
        item = None
        sub = None

    for raw in lines:
        line = raw.rstrip()

        if line.startswith("# "):
            doc["title"] = line[2:].strip()
            continue

        if line.startswith("## "):
            flush_intro()
            close_item()
            in_intro = False
            heading = line[3:].strip()
            m = re.match(r"^([0-9]+[a-z]?)\.\s+(.*)$", heading)
            number, name = (m.group(1), m.group(2)) if m else ("", heading)
            section = {"number": number, "name": name, "note": [], "items": []}
            doc["sections"].append(section)
            continue

        if line.strip() == "---":
            flush_intro()
            continue

        if re.match(r"^- \[ \] ", line):
            close_item()
            item = {"_text": [line[6:]], "subs": []}
            section["items"].append(item)
            continue

        if item is not None and re.match(r"^\s{2,}- ", line):
            sub = {"_text": [re.sub(r"^\s*- ", "", line)]}
            item["subs"].append(sub)
            continue

        if item is not None and line.startswith("  ") and line.strip():
            (sub or item)["_text"].append(line)
            continue

        if not line.strip():
            if in_intro:
                flush_intro()
            else:
                close_item()
            continue

        # Plain prose: either the document intro or a note under a heading.
        if in_intro:
            buffer.append(line)
        elif section is not None and item is None:
            section["note"].append(line)

    flush_intro()
    close_item()

    for section in doc["sections"]:
        section["note"] = unwrap(section["note"])
    return doc


# ---------------------------------------------------------------- markup


def item_id(section_index: int, index: int, text: str) -> str:
    digest = hashlib.sha1(re.sub(r"\s+", " ", text).encode()).hexdigest()[:6]
    return f"s{section_index}i{index}-{digest}"


MARK_SVG = (
    '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">'
    '<path class="g-pass" d="M5 12.6 10 17.5 19 7.5"/>'
    '<path class="g-fail" d="M7 7l10 10M17 7 7 17"/>'
    '<path class="g-blocked" d="M6.5 12h11"/>'
    "</svg>"
)

NOTE_SVG = (
    '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">'
    '<path d="M4 20h4.2L19 9.2a2.1 2.1 0 0 0-3-3L5.2 17 4 20Z"/>'
    "</svg>"
)


def render_item(section_index: int, index: int, item: dict) -> str:
    ident = item_id(section_index, index, item["text"])
    subs = ""
    if item["subs"]:
        rows = "".join(f"<li>{inline(s['text'])}</li>" for s in item["subs"])
        subs = f'<ul class="subs">{rows}</ul>'
    return f"""
      <li class="item" data-id="{ident}" data-section="{section_index}" data-status="">
        <button class="mark" type="button" aria-label="Mark passed">{MARK_SVG}</button>
        <div class="body">
          <p class="text">{inline(item['text'])}</p>
          {subs}
          <p class="note-peek" hidden></p>
          <div class="drawer" hidden>
            <div class="seg" role="group" aria-label="Result">
              <button type="button" data-set="pass">Pass</button>
              <button type="button" data-set="fail">Fail</button>
              <button type="button" data-set="blocked">Blocked</button>
              <button type="button" data-set="">Clear</button>
            </div>
            <textarea rows="2" placeholder="What happened? Device, build, steps to repeat."></textarea>
          </div>
        </div>
        <button class="note-toggle" type="button" aria-expanded="false" aria-label="Add a note or flag a problem">{NOTE_SVG}</button>
      </li>"""


def render_section(index: int, section: dict) -> str:
    items = "".join(render_item(index, i, it) for i, it in enumerate(section["items"]))
    note = f'<p class="section-note">{inline(section["note"])}</p>' if section["note"] else ""
    eyebrow = f'<span class="number">{html.escape(section["number"])}</span>' if section["number"] else ""
    return f"""
    <section class="section" id="section-{index}" data-section="{index}">
      <header class="section-head">
        {eyebrow}
        <h2>{inline(section['name'])}</h2>
        <span class="section-count" aria-hidden="true"></span>
      </header>
      {note}
      <ul class="items">{items}</ul>
    </section>"""


def render_rail(doc: dict) -> str:
    cells = []
    for i, section in enumerate(doc["sections"]):
        count = len(section["items"])
        label = f'{section["number"] or i + 1}. {section["name"]}'
        cells.append(
            f'<a class="rail-cell" href="#section-{i}" data-section="{i}" '
            f'style="flex-grow:{count}" title="{html.escape(label)}">'
            f'<span class="rail-fill"></span><span class="rail-flag"></span></a>'
        )
    return "".join(cells)


# ---------------------------------------------------------------- page

CSS = """
/* ---- sticky bar --------------------------------------------------- */
.bar{
  position:sticky; top:0; z-index:20; margin:0 -16px; padding:10px 16px 8px;
  background:color-mix(in srgb, var(--bg) 88%, transparent);
  backdrop-filter:saturate(1.4) blur(12px);
  -webkit-backdrop-filter:saturate(1.4) blur(12px);
  border-bottom:1px solid var(--line);
}
.bar-top{display:flex; align-items:baseline; gap:12px}
.bar-title{font-family:Fredoka; font-weight:600; font-size:15px; letter-spacing:.01em}
.bar-score{
  margin-left:auto; font-family:Fredoka; font-weight:600; font-size:15px;
  font-variant-numeric:tabular-nums; color:var(--accent-text);
}
.bar-score .of{color:var(--muted); font-weight:400}
.bar-flags{font-size:12px; font-weight:700; color:var(--muted); font-variant-numeric:tabular-nums}
.bar-flags .n-fail{color:var(--fail)} .bar-flags .n-blocked{color:var(--blocked)}
.bar .filters{margin-top:9px}

/* One cell per section, sized by how many items it holds. */
.rail{display:flex; gap:3px; margin-top:8px; height:12px; align-items:stretch}
.rail-cell{
  position:relative; display:block; min-width:6px; background:var(--line);
  border-radius:3px; overflow:hidden; text-decoration:none;
}
.rail-fill{
  position:absolute; inset:0 auto 0 0; width:0%; background:var(--accent);
  transition:width .28s ease;
}
.rail-flag{position:absolute; inset:auto 0 0 0; height:4px; background:var(--fail); opacity:0; transition:opacity .2s ease}
.rail-cell[data-flagged="1"] .rail-flag{opacity:.9}
.rail-cell:hover{filter:brightness(1.06)}

/* ---- masthead ----------------------------------------------------- */
.masthead{padding:28px 0 4px}
.masthead h1{font-size:clamp(26px, 6vw, 34px); line-height:1.12; letter-spacing:-.01em}
.masthead .kicker{
  font-size:12px; font-weight:800; letter-spacing:.13em; text-transform:uppercase;
  color:var(--accent-text); margin:0 0 8px;
}
.intro{display:flex; flex-direction:column; gap:10px; margin:16px 0 0; color:var(--muted); max-width:38rem}
.intro p{margin:0}
.intro strong{color:var(--ink)}

.session{
  margin:20px 0 8px; padding:14px; background:var(--surface); border:1px solid var(--line);
  border-radius:var(--radius); box-shadow:var(--shadow);
  display:flex; flex-wrap:wrap; gap:10px; align-items:flex-end;
}
.session-actions{display:flex; gap:8px; flex:1 1 100%; flex-wrap:wrap; align-items:center}
.saved{margin-left:auto; align-self:center; font-size:12px; color:var(--muted); font-variant-numeric:tabular-nums}
.legend{flex:1 1 100%; margin:0; font-size:13px; color:var(--muted); max-width:34rem}

/* ---- sections ----------------------------------------------------- */
.section{margin-top:34px; scroll-margin-top:96px}
.section-head{display:flex; align-items:center; gap:10px; padding-bottom:10px; border-bottom:1px solid var(--line)}
.section-head h2{font-size:19px; letter-spacing:-.005em}
.section-head .number{
  font-family:Fredoka; font-weight:600; font-size:12px; color:var(--accent-text);
  background:var(--accent-soft); border-radius:7px; padding:2px 7px; letter-spacing:.02em;
}
.section-count{
  margin-left:auto; font-size:12px; font-weight:800; color:var(--muted);
  font-variant-numeric:tabular-nums; letter-spacing:.02em;
}
.section-note{margin:12px 0 0; color:var(--muted); font-size:14px}
.items{list-style:none; margin:8px 0 0; padding:0; display:flex; flex-direction:column; gap:2px}

/* ---- item --------------------------------------------------------- */
.item{
  position:relative; display:flex; gap:11px; padding:11px 12px 11px 11px;
  border-radius:14px; border:1px solid transparent;
}
.item + .item{border-top:1px solid var(--line)}
.item[data-status]:not([data-status=""]){border-color:var(--line); background:var(--surface)}
.item[data-status="pass"] .text{color:var(--muted)}
.item[data-status="fail"]{background:var(--fail-soft); border-color:color-mix(in srgb, var(--fail) 34%, transparent)}
.item[data-status="blocked"]{background:var(--blocked-soft); border-color:color-mix(in srgb, var(--blocked) 34%, transparent)}
.item.hidden{display:none}

.mark{
  flex:none; width:26px; height:26px; margin-top:1px; border-radius:50%;
  border:2px solid color-mix(in srgb, var(--muted) 45%, transparent);
  background:transparent; padding:0; display:grid; place-items:center;
  transition:background .16s ease, border-color .16s ease, transform .16s ease;
}
.mark:active{transform:scale(.9)}
.mark svg{width:20px; height:20px; fill:none; stroke-width:2.6; stroke-linecap:round; stroke-linejoin:round}
.mark svg path{stroke:var(--on-accent); opacity:0}
.item[data-status="pass"] .mark{background:var(--pass); border-color:var(--pass)}
.item[data-status="pass"] .g-pass{opacity:1}
.item[data-status="fail"] .mark{background:var(--fail); border-color:var(--fail)}
.item[data-status="fail"] .g-fail{opacity:1}
.item[data-status="blocked"] .mark{background:var(--blocked); border-color:var(--blocked)}
.item[data-status="blocked"] .g-blocked{opacity:1}

.body{flex:1; min-width:0}
.text{margin:0}
.item[data-status="fail"] .text::before,
.item[data-status="blocked"] .text::before{
  font-size:11px; font-weight:800; letter-spacing:.09em; text-transform:uppercase;
  border-radius:5px; padding:1px 6px; margin-right:7px; vertical-align:2px; white-space:nowrap;
  color:var(--on-accent);
}
.item[data-status="fail"] .text::before{content:"Failed"; background:var(--fail)}
.item[data-status="blocked"] .text::before{content:"Blocked"; background:var(--blocked)}

.subs{
  margin:8px 0 0; padding:0 0 0 13px; list-style:none; border-left:2px solid var(--line);
  display:flex; flex-direction:column; gap:6px; font-size:14.5px; color:var(--muted);
}
.subs strong{color:var(--ink)}

.note-toggle{
  flex:none; align-self:flex-start; width:28px; height:28px; padding:0; border-radius:9px;
  border:1px solid transparent; background:none; display:grid; place-items:center;
  transition:background .16s ease, border-color .16s ease;
}
.note-toggle svg{width:17px; height:17px; fill:none; stroke:var(--muted); stroke-width:1.8; stroke-linejoin:round}
.note-toggle:hover{background:var(--accent-soft)}
.note-toggle:hover svg{stroke:var(--accent-text)}
.item.has-note .note-toggle{background:var(--accent-soft); border-color:color-mix(in srgb, var(--accent) 30%, transparent)}
.item.has-note .note-toggle svg{stroke:var(--accent-text)}
.note-toggle[aria-expanded="true"]{background:var(--accent); border-color:var(--accent)}
.note-toggle[aria-expanded="true"] svg{stroke:var(--on-accent)}
.note-peek{
  margin:6px 0 0; padding-left:9px; border-left:2px solid var(--accent);
  font-size:13.5px; color:var(--muted); white-space:pre-wrap;
}

.drawer{margin-top:9px; display:flex; flex-direction:column; gap:8px}
.item[data-status="pass"] .seg button[data-set="pass"]{background:var(--pass); border-color:var(--pass); color:var(--on-accent)}
.item[data-status="fail"] .seg button[data-set="fail"]{background:var(--fail); border-color:var(--fail); color:var(--on-accent)}
.item[data-status="blocked"] .seg button[data-set="blocked"]{background:var(--blocked); border-color:var(--blocked); color:var(--on-accent)}
.drawer textarea{
  width:100%; background:var(--surface2); border:1px solid var(--line); border-radius:11px;
  padding:9px 11px; font-size:14.5px; font-weight:500; resize:vertical; min-height:60px;
}

@media (max-width:520px){
  .item{padding:10px 6px}
  .section{margin-top:28px}
}
"""

JS = r"""
(function(){
  var KEY = "mochi-test-plan-v1";
  var root = document.documentElement;
  var items = Array.prototype.slice.call(document.querySelectorAll(".item"));
  var byId = {};
  items.forEach(function(el){ byId[el.dataset.id] = el; });

  var state = { meta:{tester:"", build:""}, results:{} };
  var storageOK = true;
  try {
    var stored = localStorage.getItem(KEY);
    if (stored) state = JSON.parse(stored);
    if (!state.results) state.results = {};
    if (!state.meta) state.meta = {tester:"", build:""};
  } catch (e) { storageOK = false; }

  var saveTimer = null;
  var savedEl = document.getElementById("saved");
  function save(){
    if (!storageOK) return;
    clearTimeout(saveTimer);
    saveTimer = setTimeout(function(){
      try {
        localStorage.setItem(KEY, JSON.stringify(state));
        savedEl.textContent = "Saved " + new Date().toLocaleTimeString([], {hour:"numeric", minute:"2-digit"});
      } catch (e) {
        storageOK = false;
        showStorageWarning();
      }
    }, 220);
  }
  function showStorageWarning(){
    var b = document.getElementById("storage-warning");
    if (b) b.hidden = false;
  }
  if (!storageOK) showStorageWarning();

  function result(id){
    if (!state.results[id]) state.results[id] = {status:"", note:""};
    return state.results[id];
  }

  /* ---- painting ---- */
  function paintItem(el){
    var r = result(el.dataset.id);
    el.dataset.status = r.status;
    el.classList.toggle("has-note", !!r.note);
    var peek = el.querySelector(".note-peek");
    peek.textContent = r.note;
    peek.hidden = !r.note || !el.querySelector(".drawer").hidden;
    var mark = el.querySelector(".mark");
    mark.setAttribute("aria-label",
      r.status === "pass" ? "Passed. Clear this result" :
      r.status === "fail" ? "Failed. Open the note" :
      r.status === "blocked" ? "Blocked. Open the note" : "Mark passed");
    el.querySelector(".note-toggle").setAttribute("aria-label",
      r.note ? "Edit the note on this item" : "Add a note or flag a problem");
  }

  function tally(){
    var done = 0, fail = 0, blocked = 0;
    var perSection = {};
    items.forEach(function(el){
      var s = el.dataset.section;
      if (!perSection[s]) perSection[s] = {done:0, total:0, flagged:0};
      perSection[s].total++;
      var st = result(el.dataset.id).status;
      if (st) { done++; perSection[s].done++; }
      if (st === "fail") { fail++; perSection[s].flagged++; }
      if (st === "blocked") { blocked++; perSection[s].flagged++; }
    });
    document.getElementById("score-done").textContent = done;
    document.getElementById("score-total").textContent = items.length;
    var flags = document.getElementById("bar-flags");
    var bits = [];
    if (fail) bits.push('<span class="n-fail">' + fail + " failed</span>");
    if (blocked) bits.push('<span class="n-blocked">' + blocked + " blocked</span>");
    flags.innerHTML = bits.join(" &middot; ");
    Object.keys(perSection).forEach(function(s){
      var d = perSection[s];
      var cell = document.querySelector('.rail-cell[data-section="' + s + '"]');
      if (cell) {
        cell.querySelector(".rail-fill").style.width = (d.total ? (d.done / d.total) * 100 : 0) + "%";
        cell.dataset.flagged = d.flagged ? "1" : "0";
      }
      var head = document.querySelector('.section[data-section="' + s + '"] .section-count');
      if (head) head.textContent = d.done + "/" + d.total;
    });
    return {done:done, fail:fail, blocked:blocked};
  }

  /* ---- interactions ---- */
  function setStatus(el, status){
    result(el.dataset.id).status = status;
    paintItem(el);
    tally();
    applyFilter();
    save();
  }
  function toggleDrawer(el, force){
    var drawer = el.querySelector(".drawer");
    var open = force === undefined ? drawer.hidden : force;
    drawer.hidden = !open;
    el.querySelector(".note-toggle").setAttribute("aria-expanded", open ? "true" : "false");
    paintItem(el);
    if (open) drawer.querySelector("textarea").focus();
  }

  items.forEach(function(el){
    var r = result(el.dataset.id);
    el.querySelector(".drawer textarea").value = r.note || "";
    paintItem(el);

    el.querySelector(".mark").addEventListener("click", function(){
      var st = result(el.dataset.id).status;
      if (st === "fail" || st === "blocked") { toggleDrawer(el, true); return; }
      setStatus(el, st === "pass" ? "" : "pass");
    });
    el.querySelector(".note-toggle").addEventListener("click", function(){ toggleDrawer(el); });
    el.querySelectorAll(".seg button").forEach(function(b){
      b.addEventListener("click", function(){ setStatus(el, b.dataset.set); });
    });
    var ta = el.querySelector(".drawer textarea");
    ta.addEventListener("input", function(){
      result(el.dataset.id).note = ta.value;
      el.classList.toggle("has-note", !!ta.value);
      save();
    });
    ta.addEventListener("blur", function(){ paintItem(el); });
  });

  /* ---- session fields ---- */
  ["tester", "build"].forEach(function(k){
    var input = document.getElementById("meta-" + k);
    input.value = state.meta[k] || "";
    input.addEventListener("input", function(){ state.meta[k] = input.value; save(); });
  });

  /* ---- filters ---- */
  var filter = "all";
  function matches(el){
    var r = result(el.dataset.id);
    if (filter === "open") return !r.status;
    if (filter === "flagged") return r.status === "fail" || r.status === "blocked";
    if (filter === "noted") return !!r.note;
    return true;
  }
  function applyFilter(){
    items.forEach(function(el){ el.classList.toggle("hidden", !matches(el)); });
    document.querySelectorAll(".section").forEach(function(sec){
      var any = Array.prototype.some.call(sec.querySelectorAll(".item"), function(el){
        return !el.classList.contains("hidden");
      });
      sec.hidden = !any;
    });
  }
  document.querySelectorAll(".filters button").forEach(function(b){
    b.addEventListener("click", function(){
      filter = b.dataset.filter;
      document.querySelectorAll(".filters button").forEach(function(o){
        o.setAttribute("aria-pressed", o === b ? "true" : "false");
      });
      applyFilter();
    });
  });

  /* ---- theme toggle ---- */
  var themeBtn = document.getElementById("theme-toggle");
  function currentTheme(){
    if (root.dataset.theme) return root.dataset.theme;
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }
  function paintTheme(){
    themeBtn.textContent = currentTheme() === "dark" ? "Black Sesame" : "Ube";
  }
  themeBtn.addEventListener("click", function(){
    root.dataset.theme = currentTheme() === "dark" ? "light" : "dark";
    paintTheme();
  });
  paintTheme();

  /* ---- export ---- */
  function toMarkdown(node){
    var out = "";
    Array.prototype.forEach.call(node.childNodes, function(child){
      if (child.nodeType === 3) { out += child.nodeValue; return; }
      if (child.nodeName === "STRONG") { out += "**" + toMarkdown(child) + "**"; return; }
      if (child.classList && child.classList.contains("chip")) { out += "[" + child.textContent + "]"; return; }
      out += toMarkdown(child);
    });
    return out;
  }

  function markdown(){
    var counts = tally();
    var lines = [];
    var stamp = new Date().toLocaleString();
    lines.push("# MochiBuddy manual test plan results");
    lines.push("");
    lines.push("- Tester: " + (state.meta.tester || "(unnamed)"));
    lines.push("- Build: " + (state.meta.build || "(not recorded)"));
    lines.push("- Run finished: " + stamp);
    lines.push("- Checked " + counts.done + " of " + items.length +
      ", " + counts.fail + " failed, " + counts.blocked + " blocked");
    lines.push("");
    document.querySelectorAll(".section").forEach(function(sec){
      var head = sec.querySelector(".section-head");
      var number = head.querySelector(".number");
      var name = toMarkdown(head.querySelector("h2")).trim();
      lines.push("## " + (number ? number.textContent + ". " : "") + name);
      lines.push("");
      sec.querySelectorAll(".item").forEach(function(el){
        var r = result(el.dataset.id);
        var text = toMarkdown(el.querySelector(".text")).replace(/\s+/g, " ").trim();
        var box = r.status === "pass" ? "x" : " ";
        var tag = r.status === "fail" ? "**FAIL** " : r.status === "blocked" ? "**BLOCKED** " : "";
        lines.push("- [" + box + "] " + tag + text);
        if (r.note) {
          r.note.split("\n").forEach(function(line, i){
            lines.push("  " + (i === 0 ? "- note: " : "    ") + line);
          });
        }
      });
      lines.push("");
    });
    return lines.join("\n");
  }

  var sheet = document.getElementById("export-sheet");
  var sheetText = document.getElementById("export-text");
  function openSheet(){
    sheetText.value = markdown();
    sheet.setAttribute("open", "");
    sheetText.scrollTop = 0;
    document.getElementById("sheet-copy").focus();
  }
  function closeSheet(){ sheet.removeAttribute("open"); }
  document.getElementById("export").addEventListener("click", openSheet);
  document.getElementById("sheet-close").addEventListener("click", closeSheet);
  sheet.addEventListener("click", function(e){ if (e.target === sheet) closeSheet(); });
  document.addEventListener("keydown", function(e){ if (e.key === "Escape") closeSheet(); });

  document.getElementById("sheet-copy").addEventListener("click", function(){
    var btn = this;
    sheetText.select();
    var done = function(){ btn.textContent = "Copied"; setTimeout(function(){ btn.textContent = "Copy"; }, 1600); };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(sheetText.value).then(done, function(){
        try { document.execCommand("copy"); done(); } catch (e) { btn.textContent = "Select all and copy"; }
      });
    } else {
      try { document.execCommand("copy"); done(); } catch (e) { btn.textContent = "Select all and copy"; }
    }
  });
  document.getElementById("sheet-download").addEventListener("click", function(){
    try {
      var blob = new Blob([sheetText.value], {type:"text/markdown"});
      var a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = "manual-test-plan-results.md";
      document.body.appendChild(a);
      a.click();
      setTimeout(function(){ URL.revokeObjectURL(a.href); a.remove(); }, 1000);
    } catch (e) {
      this.textContent = "Download blocked, copy instead";
    }
  });

  /* ---- reset ---- */
  var resetBtn = document.getElementById("reset");
  var resetTimer = null;
  resetBtn.addEventListener("click", function(){
    if (resetBtn.dataset.armed !== "1") {
      resetBtn.dataset.armed = "1";
      resetBtn.textContent = "Tap again to clear everything";
      resetTimer = setTimeout(function(){
        resetBtn.dataset.armed = "0";
        resetBtn.textContent = "Reset run";
      }, 4000);
      return;
    }
    clearTimeout(resetTimer);
    state.results = {};
    items.forEach(function(el){
      el.querySelector(".drawer textarea").value = "";
      el.querySelector(".drawer").hidden = true;
      paintItem(el);
    });
    tally();
    applyFilter();
    save();
    resetBtn.dataset.armed = "0";
    resetBtn.textContent = "Reset run";
  });

  tally();
  applyFilter();
})();
"""


def build(bug_log_url: str = "") -> str:
    doc = parse(SOURCE.read_text())
    total = sum(len(s["items"]) for s in doc["sections"])
    sections = "".join(render_section(i, s) for i, s in enumerate(doc["sections"]))
    intro = "".join(f"<p>{inline(p)}</p>" for p in doc["intro"])
    bug_link = (
        f'<a class="btn" href="{html.escape(bug_log_url)}" target="_blank" rel="noopener">Log a bug</a>'
        if bug_log_url
        else ""
    )

    return f"""<title>{html.escape(doc['title'])}</title>
<style>
{fonts_css()}{BASE_CSS}{CSS}</style>

<div class="wrap">
  <header class="bar">
    <div class="bar-top">
      <span class="bar-title">Test plan</span>
      <span class="bar-flags" id="bar-flags"></span>
      <span class="bar-score"><span id="score-done">0</span><span class="of"> / <span id="score-total">{total}</span></span></span>
    </div>
    <nav class="rail" aria-label="Jump to a section">{render_rail(doc)}</nav>
    <div class="filters" role="group" aria-label="Filter items">
      <button type="button" data-filter="all" aria-pressed="true">Everything</button>
      <button type="button" data-filter="open" aria-pressed="false">Not yet run</button>
      <button type="button" data-filter="flagged" aria-pressed="false">Failed or blocked</button>
      <button type="button" data-filter="noted" aria-pressed="false">With notes</button>
    </div>
  </header>

  <div class="masthead">
    <p class="kicker">MochiBuddy QA</p>
    <h1>{inline(doc['title'].replace('MochiBuddy ', '').capitalize())}</h1>
    <div class="intro">{intro}</div>
  </div>

  <div class="session">
    <div class="field">
      <label for="meta-tester">Tester</label>
      <input id="meta-tester" type="text" autocomplete="name" placeholder="Your name">
    </div>
    <div class="field">
      <label for="meta-build">Build</label>
      <input id="meta-build" type="text" placeholder="TestFlight 1.0 (42)">
    </div>
    <div class="session-actions">
      <button class="btn primary" id="export" type="button">Export results</button>
      {bug_link}
      <button class="btn danger" id="reset" type="button">Reset run</button>
      <button class="btn" id="theme-toggle" type="button" aria-label="Switch flavor">Ube</button>
      <span class="saved" id="saved">Progress saves as you go</span>
    </div>
    <p class="legend">
      Tap the circle when an item passes. Tap the pencil to write a note, or to mark
      the item failed or blocked.
    </p>
  </div>
  <p class="warn-banner" id="storage-warning" hidden>
    This browser will not let the page save progress locally, so a reload loses your results.
    Export before you close the tab.
  </p>

  {sections}

  <p class="foot">
    Generated from <code>manual-test-plan.md</code>. Edit the markdown, then run
    <code>python3 tools/build-test-plan-page.py</code> to rebuild this page.
    Results live in this browser only, on this device.
  </p>
</div>

<div class="sheet" id="export-sheet" role="dialog" aria-modal="true" aria-label="Export results">
  <div class="sheet-card">
    <h3>Results as markdown</h3>
    <p>Paste this into the pull request, a bug ticket, or back into the repo.</p>
    <textarea id="export-text" readonly spellcheck="false"></textarea>
    <div class="sheet-actions">
      <button class="btn primary" id="sheet-copy" type="button">Copy</button>
      <button class="btn" id="sheet-download" type="button">Download .md</button>
      <button class="btn" id="sheet-close" type="button">Close</button>
    </div>
  </div>
</div>

<script>
{JS}
</script>
"""


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--bug-log",
        default="",
        metavar="URL",
        help="link the checklist to a published bug log page",
    )
    args = ap.parse_args()

    page = build(args.bug_log)
    write(OUTPUT, page)
    doc = parse(SOURCE.read_text())
    total = sum(len(s["items"]) for s in doc["sections"])
    subs = sum(len(i["subs"]) for s in doc["sections"] for i in s["items"])
    print(
        f"{OUTPUT.relative_to(ROOT)}: {len(doc['sections'])} sections, "
        f"{total} items, {subs} sub-points, {len(page) // 1024} KB"
    )


if __name__ == "__main__":
    main()
