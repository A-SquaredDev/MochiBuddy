#!/usr/bin/env python3
"""Build tools/bug-log.html, the page that writes and re-reads bugs.md.

    python3 tools/build-bug-log-page.py

The page keeps bugs in the browser as you type and writes them out as
markdown. In Chrome on a Mac it can save straight into bugs.md and open it
again later, so the file in the repo is the record. On iOS, where browsers
cannot write files, use Download or Copy and paste into bugs.md.

The Area menu is built from the section headings in manual-test-plan.md, so
rerun this whenever the plan gains or loses a section.
"""

from __future__ import annotations

import html
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mochi_page import BASE_CSS, ROOT, fonts_css, write  # noqa: E402

PLAN = ROOT / "manual-test-plan.md"
BUGS = ROOT / "bugs.md"
OUTPUT = ROOT / "tools" / "bug-log.html"

SEVERITIES = ["Blocker", "Major", "Minor", "Polish"]
STATUSES = ["Open", "Fixed", "Won't fix"]


def plan_areas() -> list[str]:
    """Section headings from the test plan, so a bug can name where it lives."""
    headings = re.findall(r"^## (.+)$", PLAN.read_text(), flags=re.M)
    cleaned = [re.sub(r"\s*\[needs [^\]]+\]", "", h).strip() for h in headings]
    return cleaned + ["Somewhere else"]


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
.bar .filters{margin-top:9px}

/* ---- masthead ----------------------------------------------------- */
.masthead{padding:28px 0 4px}
.masthead h1{font-size:clamp(26px, 6vw, 34px); line-height:1.12; letter-spacing:-.01em}
.masthead .kicker{
  font-size:12px; font-weight:800; letter-spacing:.13em; text-transform:uppercase;
  color:var(--accent-text); margin:0 0 8px;
}
.lede{margin:14px 0 0; color:var(--muted); max-width:38rem}
.lede + .lede{margin-top:10px}

.filebar{
  margin:20px 0 0; padding:14px; background:var(--surface); border:1px solid var(--line);
  border-radius:var(--radius); box-shadow:var(--shadow);
  display:flex; flex-wrap:wrap; gap:8px; align-items:center;
}
.filebar .where{
  flex:1 1 100%; margin:0; font-size:13px; color:var(--muted);
  font-variant-numeric:tabular-nums;
}
.filebar .where b{color:var(--ink); font-weight:800}

/* ---- the form ----------------------------------------------------- */
.form{
  margin:14px 0 0; padding:16px; background:var(--surface); border:1px solid var(--line);
  border-radius:var(--radius); box-shadow:var(--shadow);
  display:flex; flex-wrap:wrap; gap:12px;
}
.form.editing{border-color:var(--accent); box-shadow:0 0 0 3px var(--accent-soft), var(--shadow)}
.form h2{flex:1 1 100%; font-size:17px}
.form .wide{flex:1 1 100%}
.form .half{flex:1 1 210px}
.form-actions{flex:1 1 100%; display:flex; gap:8px; align-items:center; flex-wrap:wrap}
.form-error{color:var(--fail); font-size:13px; font-weight:800}
.sev-pick{flex:1 1 210px; display:flex; flex-direction:column; gap:4px}
.sev-pick .label{font-size:11px; font-weight:800; letter-spacing:.09em; text-transform:uppercase; color:var(--muted)}
.sev-pick .seg button[aria-pressed="true"][data-sev="Blocker"]{background:var(--fail); border-color:var(--fail)}
.sev-pick .seg button[aria-pressed="true"][data-sev="Major"]{background:var(--blocked); border-color:var(--blocked)}

/* ---- the list ----------------------------------------------------- */
.list{display:flex; flex-direction:column; gap:10px; margin-top:26px}
.list-head{display:flex; align-items:baseline; gap:10px; padding-bottom:10px; border-bottom:1px solid var(--line)}
.list-head h2{font-size:19px}
.list-count{margin-left:auto; font-size:12px; font-weight:800; color:var(--muted); font-variant-numeric:tabular-nums}

.empty{
  margin-top:16px; padding:22px 18px; border:1px dashed var(--line); border-radius:var(--radius);
  color:var(--muted); text-align:center;
}

.bug{
  padding:14px; background:var(--surface); border:1px solid var(--line);
  border-left:4px solid var(--muted); border-radius:14px; box-shadow:var(--shadow);
  display:flex; flex-direction:column; gap:9px;
}
.bug[data-sev="Blocker"]{border-left-color:var(--fail)}
.bug[data-sev="Major"]{border-left-color:var(--blocked)}
.bug[data-sev="Minor"]{border-left-color:var(--accent)}
.bug[data-sev="Polish"]{border-left-color:var(--muted)}
.bug[data-status="Fixed"], .bug[data-status="Won't fix"]{background:var(--surface2)}
.bug[data-status="Fixed"] .bug-title, .bug[data-status="Won't fix"] .bug-title{color:var(--muted)}

.bug-top{display:flex; align-items:center; gap:8px; flex-wrap:wrap}
.bug-id{
  font-family:ui-monospace, SFMono-Regular, Menlo, monospace; font-size:12px; font-weight:700;
  color:var(--muted); letter-spacing:.02em;
}
.tag{
  font-size:11px; font-weight:800; letter-spacing:.06em; text-transform:uppercase;
  border-radius:6px; padding:2px 7px; white-space:nowrap;
}
.tag-sev{background:var(--accent-soft); color:var(--accent-text)}
.bug[data-sev="Blocker"] .tag-sev{background:var(--fail); color:var(--on-accent)}
.bug[data-sev="Major"] .tag-sev{background:var(--blocked); color:var(--on-accent)}
.bug[data-sev="Polish"] .tag-sev{background:var(--line); color:var(--muted)}
.tag-status{border:1px solid var(--line); color:var(--muted)}
.bug[data-status="Open"] .tag-status{border-color:color-mix(in srgb, var(--fail) 40%, transparent); color:var(--fail)}
.bug[data-status="Fixed"] .tag-status{border-color:color-mix(in srgb, var(--pass) 45%, transparent); color:var(--pass)}

.bug-title{margin:0; font-size:17px; flex:1 1 100%}
.bug-meta{margin:0; font-size:13px; color:var(--muted)}
.bug-body{margin:0; display:flex; flex-direction:column; gap:8px; font-size:14.5px}
.bug-body h4{
  margin:0 0 2px; font-family:Nunito; font-size:11px; font-weight:800; letter-spacing:.09em;
  text-transform:uppercase; color:var(--muted);
}
.bug-body p{margin:0; white-space:pre-wrap}
.bug-body ol{margin:0; padding-left:20px; display:flex; flex-direction:column; gap:3px}
.bug-actions{display:flex; gap:6px; align-items:center; flex-wrap:wrap; padding-top:2px}
.bug-actions .seg{margin-right:auto}
.btn-small{
  border:1px solid var(--line); background:var(--surface2); border-radius:9px;
  padding:4px 10px; font-size:13px; font-weight:700; color:var(--muted);
}
.btn-small:hover{color:var(--ink)}
.btn-small[data-armed="1"]{border-color:var(--fail); color:var(--fail); background:var(--fail-soft)}

@media (max-width:520px){
  .bug-actions .seg{margin-right:0; flex:1 1 100%}
}
"""

JS = r"""
(function(){
  var KEY = "mochi-bug-log-v1";
  var SEVERITIES = __SEVERITIES__;
  var STATUSES = __STATUSES__;
  var root = document.documentElement;

  var state = {nextId: 1, bugs: [], meta: {device: "", build: ""}};
  var storageOK = true;
  try {
    var stored = localStorage.getItem(KEY);
    if (stored) state = JSON.parse(stored);
    if (!state.bugs) state.bugs = [];
    if (!state.meta) state.meta = {device: "", build: ""};
    if (!state.nextId) state.nextId = 1;
  } catch (e) { storageOK = false; }
  if (!storageOK) document.getElementById("storage-warning").hidden = false;

  var dirty = false;
  function save(){
    dirty = true;
    paintWhere();
    if (!storageOK) return;
    try { localStorage.setItem(KEY, JSON.stringify(state)); }
    catch (e) { storageOK = false; document.getElementById("storage-warning").hidden = false; }
  }

  function esc(s){
    return String(s == null ? "" : s).replace(/[&<>"]/g, function(c){
      return {"&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;"}[c];
    });
  }
  function today(){
    var d = new Date();
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") +
      "-" + String(d.getDate()).padStart(2, "0");
  }
  function idFor(n){ return "BUG-" + String(n).padStart(3, "0"); }
  function stepLines(text){
    return String(text || "").split("\n").map(function(l){ return l.trim(); }).filter(Boolean);
  }

  /* ---- the form ---- */
  var form = document.getElementById("form");
  var fields = {};
  ["title", "area", "device", "build", "steps", "expected", "actual", "notes"].forEach(function(k){
    fields[k] = document.getElementById("f-" + k);
  });
  var severity = "Major";
  var editingId = null;

  fields.device.value = state.meta.device || "";
  fields.build.value = state.meta.build || "";

  function paintSeverity(){
    document.querySelectorAll("#sev-pick button").forEach(function(b){
      b.setAttribute("aria-pressed", b.dataset.sev === severity ? "true" : "false");
    });
  }
  document.querySelectorAll("#sev-pick button").forEach(function(b){
    b.addEventListener("click", function(){ severity = b.dataset.sev; paintSeverity(); });
  });
  paintSeverity();

  function resetForm(){
    editingId = null;
    ["title", "steps", "expected", "actual", "notes"].forEach(function(k){ fields[k].value = ""; });
    severity = "Major";
    paintSeverity();
    form.classList.remove("editing");
    document.getElementById("form-title").textContent = "Log a bug";
    document.getElementById("submit").textContent = "Add bug";
    document.getElementById("cancel").hidden = true;
    document.getElementById("form-error").textContent = "";
  }

  function loadIntoForm(bug){
    editingId = bug.id;
    fields.title.value = bug.title || "";
    fields.area.value = bug.area || fields.area.options[0].value;
    fields.device.value = bug.device || "";
    fields.build.value = bug.build || "";
    fields.steps.value = bug.steps || "";
    fields.expected.value = bug.expected || "";
    fields.actual.value = bug.actual || "";
    fields.notes.value = bug.notes || "";
    severity = bug.severity || "Major";
    paintSeverity();
    form.classList.add("editing");
    document.getElementById("form-title").textContent = "Editing " + bug.id;
    document.getElementById("submit").textContent = "Save changes";
    document.getElementById("cancel").hidden = false;
    form.scrollIntoView({behavior: "smooth", block: "start"});
    fields.title.focus();
  }

  document.getElementById("submit").addEventListener("click", function(){
    var title = fields.title.value.trim();
    if (!title) {
      document.getElementById("form-error").textContent = "Give the bug a one-line title first.";
      fields.title.focus();
      return;
    }
    document.getElementById("form-error").textContent = "";
    state.meta.device = fields.device.value.trim();
    state.meta.build = fields.build.value.trim();

    var payload = {
      title: title,
      area: fields.area.value,
      severity: severity,
      device: fields.device.value.trim(),
      build: fields.build.value.trim(),
      steps: fields.steps.value.trim(),
      expected: fields.expected.value.trim(),
      actual: fields.actual.value.trim(),
      notes: fields.notes.value.trim()
    };

    if (editingId) {
      state.bugs.forEach(function(b){
        if (b.id === editingId) { for (var k in payload) b[k] = payload[k]; }
      });
    } else {
      payload.id = idFor(state.nextId++);
      payload.status = "Open";
      payload.found = today();
      state.bugs.unshift(payload);
    }
    save();
    resetForm();
    render();
  });
  document.getElementById("cancel").addEventListener("click", function(){ resetForm(); });

  /* ---- the list ---- */
  var filter = "All";
  document.querySelectorAll(".filters button").forEach(function(b){
    b.addEventListener("click", function(){
      filter = b.dataset.filter;
      document.querySelectorAll(".filters button").forEach(function(o){
        o.setAttribute("aria-pressed", o === b ? "true" : "false");
      });
      render();
    });
  });

  function block(label, value){
    if (!value) return "";
    return "<div><h4>" + label + "</h4><p>" + esc(value) + "</p></div>";
  }

  function render(){
    var list = document.getElementById("list");
    var shown = state.bugs.filter(function(b){ return filter === "All" || b.status === filter; });
    list.innerHTML = shown.map(function(b){
      var steps = stepLines(b.steps);
      var stepsHtml = steps.length
        ? "<div><h4>Steps</h4><ol>" + steps.map(function(s){ return "<li>" + esc(s) + "</li>"; }).join("") + "</ol></div>"
        : "";
      var meta = [b.area, b.device, b.build, b.found ? "Found " + b.found : ""]
        .filter(Boolean).map(esc).join(" &middot; ");
      return '<article class="bug" data-id="' + esc(b.id) + '" data-sev="' + esc(b.severity) +
        '" data-status="' + esc(b.status) + '">' +
        '<div class="bug-top">' +
          '<span class="bug-id">' + esc(b.id) + "</span>" +
          '<span class="tag tag-sev">' + esc(b.severity) + "</span>" +
          '<span class="tag tag-status">' + esc(b.status) + "</span>" +
          '<h3 class="bug-title">' + esc(b.title) + "</h3>" +
        "</div>" +
        (meta ? '<p class="bug-meta">' + meta + "</p>" : "") +
        '<div class="bug-body">' + stepsHtml + block("Expected", b.expected) +
          block("Actual", b.actual) + block("Notes", b.notes) + "</div>" +
        '<div class="bug-actions">' +
          '<div class="seg" role="group" aria-label="Status">' +
            STATUSES.map(function(s){
              return '<button type="button" data-status="' + esc(s) + '" aria-pressed="' +
                (b.status === s ? "true" : "false") + '">' + esc(s) + "</button>";
            }).join("") +
          "</div>" +
          '<button class="btn-small" data-edit="1" type="button">Edit</button>' +
          '<button class="btn-small" data-delete="1" type="button">Delete</button>' +
        "</div>" +
      "</article>";
    }).join("");

    document.getElementById("empty").hidden = shown.length > 0;
    document.getElementById("empty").textContent = state.bugs.length
      ? "No bugs match this filter."
      : "No bugs logged yet. When the test plan turns up something, write it down here.";
    document.getElementById("list-count").textContent = shown.length + " shown";

    var open = state.bugs.filter(function(b){ return b.status === "Open"; }).length;
    document.getElementById("score-open").textContent = open;
    document.getElementById("score-total").textContent = state.bugs.length;
  }

  document.getElementById("list").addEventListener("click", function(e){
    var card = e.target.closest(".bug");
    if (!card) return;
    var bug = state.bugs.filter(function(b){ return b.id === card.dataset.id; })[0];
    if (!bug) return;

    if (e.target.dataset.status) {
      bug.status = e.target.dataset.status;
      save();
      render();
      return;
    }
    if (e.target.dataset.edit) { loadIntoForm(bug); return; }
    if (e.target.dataset.delete) {
      var btn = e.target;
      if (btn.dataset.armed !== "1") {
        btn.dataset.armed = "1";
        btn.textContent = "Really delete?";
        setTimeout(function(){
          if (btn.isConnected) { btn.dataset.armed = "0"; btn.textContent = "Delete"; }
        }, 4000);
        return;
      }
      state.bugs = state.bugs.filter(function(b){ return b.id !== bug.id; });
      if (editingId === bug.id) resetForm();
      save();
      render();
    }
  });

  /* ---- markdown out ---- */
  function markdown(){
    var counts = {};
    STATUSES.forEach(function(s){
      counts[s] = state.bugs.filter(function(b){ return b.status === s; }).length;
    });
    var out = [];
    out.push("# MochiBuddy bug log");
    out.push("");
    out.push("Bugs found while walking manual-test-plan.md. This file is written and read");
    out.push("back by tools/bug-log.html, so keep the shape of each entry. Editing the");
    out.push("fields by hand is fine.");
    out.push("");
    out.push(STATUSES.map(function(s){ return s + ": " + counts[s]; }).join(" | ") +
      " | Updated " + today());
    out.push("");
    state.bugs.forEach(function(b){
      out.push("## " + b.id + " " + b.title);
      out.push("");
      out.push("- Status: " + b.status);
      out.push("- Severity: " + b.severity);
      out.push("- Area: " + b.area);
      if (b.device) out.push("- Device: " + b.device);
      if (b.build) out.push("- Build: " + b.build);
      out.push("- Found: " + b.found);
      out.push("");
      var steps = stepLines(b.steps);
      if (steps.length) {
        out.push("**Steps**");
        out.push("");
        steps.forEach(function(s, i){ out.push((i + 1) + ". " + s); });
        out.push("");
      }
      if (b.expected) { out.push("**Expected:** " + b.expected); out.push(""); }
      if (b.actual) { out.push("**Actual:** " + b.actual); out.push(""); }
      if (b.notes) { out.push("**Notes:** " + b.notes); out.push(""); }
    });
    if (!state.bugs.length) { out.push("No bugs logged yet."); out.push(""); }
    return out.join("\n");
  }

  /* ---- markdown back in ---- */
  function parseMarkdown(text){
    var bugs = [];
    text.split(/\n(?=## )/).forEach(function(block){
      var head = block.match(/^## +(BUG-\d+)[ .:-]*(.*)$/m);
      if (!head) return;
      var body = block.slice(block.indexOf("\n") + 1);
      function field(name){
        var m = body.match(new RegExp("^- " + name + ":[ \\t]*(.*)$", "m"));
        return m ? m[1].trim() : "";
      }
      function section(name){
        var m = body.match(new RegExp(
          "\\*\\*" + name + ":\\*\\*[ \\t]*([\\s\\S]*?)(?=\\n\\*\\*[A-Z]|\\n## |$)"));
        return m ? m[1].trim() : "";
      }
      var stepsBlock = body.match(/\*\*Steps\*\*\s*\n([\s\S]*?)(?=\n\*\*[A-Z]|\n## |$)/);
      var steps = stepsBlock
        ? stepsBlock[1].split("\n").map(function(l){ return l.replace(/^\s*\d+[.)]\s*/, "").trim(); })
            .filter(Boolean).join("\n")
        : "";
      var status = field("Status");
      var severity = field("Severity");
      if (STATUSES.indexOf(status) < 0) status = "Open";
      if (SEVERITIES.indexOf(severity) < 0) severity = "Major";
      bugs.push({
        id: head[1], title: head[2].trim() || "(untitled)",
        status: status, severity: severity, area: field("Area"),
        device: field("Device"), build: field("Build"), found: field("Found") || today(),
        steps: steps, expected: section("Expected"), actual: section("Actual"), notes: section("Notes")
      });
    });
    return bugs;
  }

  function adopt(bugs){
    state.bugs = bugs;
    var highest = 0;
    bugs.forEach(function(b){
      var n = parseInt(String(b.id).replace(/\D/g, ""), 10);
      if (n > highest) highest = n;
    });
    state.nextId = highest + 1;
    save();
    dirty = false;
    render();
    paintWhere();
  }

  /* ---- the file itself ---- */
  var handle = null;
  var canPickFiles = typeof window.showSaveFilePicker === "function";
  var whereEl = document.getElementById("where");
  var lastSaved = "";

  function paintWhere(){
    if (handle) {
      whereEl.innerHTML = "Writing to <b>" + esc(handle.name) + "</b>. " +
        (dirty ? "Unsaved changes." : "Saved " + lastSaved + ".");
    } else if (canPickFiles) {
      whereEl.innerHTML = "Not connected to a file yet. <b>Save to bugs.md</b> picks one, " +
        "then later saves go straight there.";
    } else {
      whereEl.innerHTML = "This browser cannot write files. Use <b>Download</b> or " +
        "<b>Copy</b> and paste into <b>bugs.md</b>.";
    }
  }

  async function ensureWritable(h){
    if (!h.queryPermission) return true;
    if (await h.queryPermission({mode: "readwrite"}) === "granted") return true;
    return await h.requestPermission({mode: "readwrite"}) === "granted";
  }

  document.getElementById("save").addEventListener("click", async function(){
    var text = markdown();
    if (!canPickFiles) { openSheet(); return; }
    try {
      if (!handle) {
        handle = await window.showSaveFilePicker({
          suggestedName: "bugs.md",
          types: [{description: "Markdown", accept: {"text/markdown": [".md"]}}]
        });
      }
      if (!(await ensureWritable(handle))) { handle = null; paintWhere(); return; }
      var stream = await handle.createWritable();
      await stream.write(text);
      await stream.close();
      dirty = false;
      lastSaved = new Date().toLocaleTimeString([], {hour: "numeric", minute: "2-digit"});
      paintWhere();
    } catch (e) {
      if (e && e.name === "AbortError") return;
      /* Some hosts (an embedded page, a locked-down browser) refuse the picker.
         Hand over the markdown instead of dead-ending. */
      handle = null;
      whereEl.innerHTML = "This page cannot write files here, so copy the markdown " +
        "into <b>bugs.md</b> yourself. Opening <b>tools/bug-log.html</b> straight from " +
        "the repo in Chrome gets you the direct save.";
      openSheet();
    }
  });

  document.getElementById("open").addEventListener("click", async function(){
    if (typeof window.showOpenFilePicker === "function") {
      try {
        var picked = await window.showOpenFilePicker({
          types: [{description: "Markdown", accept: {"text/markdown": [".md"]}}]
        });
        handle = picked[0];
        var file = await handle.getFile();
        adopt(parseMarkdown(await file.text()));
        lastSaved = "on open";
        paintWhere();
      } catch (e) {
        if (e && e.name === "AbortError") return;
        handle = null;
        document.getElementById("file-input").click();
      }
      return;
    }
    document.getElementById("file-input").click();
  });

  document.getElementById("file-input").addEventListener("change", function(){
    var file = this.files && this.files[0];
    if (!file) return;
    var reader = new FileReader();
    reader.onload = function(){
      adopt(parseMarkdown(String(reader.result)));
      whereEl.innerHTML = "Loaded <b>" + esc(file.name) + "</b>. This browser cannot write " +
        "back, so use Download or Copy when you are done.";
    };
    reader.readAsText(file);
    this.value = "";
  });

  document.getElementById("download").addEventListener("click", function(){
    try {
      var blob = new Blob([markdown()], {type: "text/markdown"});
      var a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = "bugs.md";
      document.body.appendChild(a);
      a.click();
      setTimeout(function(){ URL.revokeObjectURL(a.href); a.remove(); }, 1000);
    } catch (e) { openSheet(); }
  });

  /* ---- the copy sheet ---- */
  var sheet = document.getElementById("md-sheet");
  var sheetText = document.getElementById("md-text");
  function openSheet(){
    sheetText.value = markdown();
    sheet.setAttribute("open", "");
    sheetText.scrollTop = 0;
    document.getElementById("sheet-copy").focus();
  }
  function closeSheet(){ sheet.removeAttribute("open"); }
  document.getElementById("copy").addEventListener("click", openSheet);
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

  /* ---- theme ---- */
  var themeBtn = document.getElementById("theme-toggle");
  function currentTheme(){
    if (root.dataset.theme) return root.dataset.theme;
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }
  function paintTheme(){ themeBtn.textContent = currentTheme() === "dark" ? "Black Sesame" : "Ube"; }
  themeBtn.addEventListener("click", function(){
    root.dataset.theme = currentTheme() === "dark" ? "light" : "dark";
    paintTheme();
  });
  paintTheme();

  window.addEventListener("beforeunload", function(e){
    if (dirty && state.bugs.length) { e.preventDefault(); e.returnValue = ""; }
  });

  paintWhere();
  render();
})();
"""


PAGE = """<title>MochiBuddy bug log</title>
<style>
__CSS__</style>

<div class="wrap">
  <header class="bar">
    <div class="bar-top">
      <span class="bar-title">Bug log</span>
      <span class="bar-score"><span id="score-open">0</span> open<span class="of"> of <span id="score-total">0</span></span></span>
    </div>
    <div class="filters" role="group" aria-label="Filter bugs">
      __FILTERS__
    </div>
  </header>

  <div class="masthead">
    <p class="kicker">MochiBuddy QA</p>
    <h1>Bug log</h1>
    <p class="lede">
      Anything the manual test plan turns up goes here. Write it while it is fresh:
      what you did, what you expected, what you got. Saving writes the whole log to
      <code>bugs.md</code> in the repo.
    </p>
    <p class="lede">
      Bugs live in this browser until you save. Chrome on a Mac can write straight
      into the file; on a phone, use Download or Copy and paste it in.
    </p>
  </div>

  <div class="filebar">
    <button class="btn primary" id="save" type="button">Save to bugs.md</button>
    <button class="btn" id="open" type="button">Open bugs.md</button>
    <button class="btn" id="download" type="button">Download</button>
    <button class="btn" id="copy" type="button">Copy markdown</button>
    <button class="btn" id="theme-toggle" type="button" aria-label="Switch flavor">Ube</button>
    <input type="file" id="file-input" accept=".md,.markdown,text/markdown,text/plain" hidden>
    <p class="where" id="where"></p>
  </div>
  <p class="warn-banner" id="storage-warning" hidden>
    This browser will not let the page keep bugs locally, so a reload loses anything
    unsaved. Save or copy often.
  </p>

  <div class="form" id="form">
    <h2 id="form-title">Log a bug</h2>
    <div class="field wide">
      <label for="f-title">What went wrong</label>
      <input id="f-title" type="text" placeholder="Paywall shows fallback prices on a good network">
    </div>
    <div class="field half">
      <label for="f-area">Where in the plan</label>
      <select id="f-area">__AREAS__</select>
    </div>
    <div class="sev-pick">
      <span class="label" id="sev-label">Severity</span>
      <div class="seg" id="sev-pick" role="group" aria-labelledby="sev-label">__SEVERITIES__</div>
    </div>
    <div class="field half">
      <label for="f-device">Device</label>
      <input id="f-device" type="text" placeholder="iPhone 15 Pro, iOS 18.5">
    </div>
    <div class="field half">
      <label for="f-build">Build</label>
      <input id="f-build" type="text" placeholder="TestFlight 1.0 (42)">
    </div>
    <div class="field wide">
      <label for="f-steps">Steps, one per line</label>
      <textarea id="f-steps" rows="3" placeholder="Fresh install&#10;Sign in with Apple&#10;Reach the paywall"></textarea>
    </div>
    <div class="field half">
      <label for="f-expected">Expected</label>
      <textarea id="f-expected" rows="2" placeholder="Real localized prices"></textarea>
    </div>
    <div class="field half">
      <label for="f-actual">Actual</label>
      <textarea id="f-actual" rows="2" placeholder="$3.99 / $29.99 fallback"></textarea>
    </div>
    <div class="field wide">
      <label for="f-notes">Notes</label>
      <textarea id="f-notes" rows="2" placeholder="Happened twice, both on wifi. Console showed a StoreKit timeout."></textarea>
    </div>
    <div class="form-actions">
      <button class="btn primary" id="submit" type="button">Add bug</button>
      <button class="btn" id="cancel" type="button" hidden>Cancel</button>
      <span class="form-error" id="form-error"></span>
    </div>
  </div>

  <div class="list-head">
    <h2>Logged</h2>
    <span class="list-count" id="list-count">0 shown</span>
  </div>
  <p class="empty" id="empty" hidden></p>
  <div class="list" id="list"></div>

  <p class="foot">
    Generated by <code>tools/build-bug-log-page.py</code>; the Area menu follows the
    section headings in <code>manual-test-plan.md</code>. The saved file, <code>bugs.md</code>,
    is the record; this page is just a nicer way to write it.
  </p>
</div>

<div class="sheet" id="md-sheet" role="dialog" aria-modal="true" aria-label="Bug log as markdown">
  <div class="sheet-card">
    <h3>bugs.md</h3>
    <p>Copy this and paste it into bugs.md, replacing the whole file.</p>
    <textarea id="md-text" readonly spellcheck="false"></textarea>
    <div class="sheet-actions">
      <button class="btn primary" id="sheet-copy" type="button">Copy</button>
      <button class="btn" id="sheet-close" type="button">Close</button>
    </div>
  </div>
</div>

<script>
__JS__
</script>
"""


def build() -> str:
    areas = plan_areas()
    options = "".join(f'<option value="{html.escape(a)}">{html.escape(a)}</option>' for a in areas)
    severities = "".join(
        f'<button type="button" data-sev="{s}" aria-pressed="'
        f'{"true" if s == "Major" else "false"}">{s}</button>'
        for s in SEVERITIES
    )
    filters = "".join(
        f'<button type="button" data-filter="{html.escape(f)}" aria-pressed="'
        f'{"true" if f == "All" else "false"}">{html.escape(f)}</button>'
        for f in ["All"] + STATUSES
    )
    js = (
        JS.replace("__SEVERITIES__", json.dumps(SEVERITIES))
        .replace("__STATUSES__", json.dumps(STATUSES))
    )
    return (
        PAGE.replace("__CSS__", fonts_css() + BASE_CSS + CSS)
        .replace("__AREAS__", options)
        .replace("__SEVERITIES__", severities)
        .replace("__FILTERS__", filters)
        .replace("__JS__", js)
    )


def seed_bugs_md() -> bool:
    """Give the reference from the test plan something real to point at."""
    if BUGS.exists():
        return False
    BUGS.write_text(
        "# MochiBuddy bug log\n"
        "\n"
        "Bugs found while walking manual-test-plan.md. This file is written and read\n"
        "back by tools/bug-log.html, so keep the shape of each entry. Editing the\n"
        "fields by hand is fine.\n"
        "\n"
        "Open: 0 | Fixed: 0 | Won't fix: 0\n"
        "\n"
        "No bugs logged yet.\n"
    )
    return True


def main() -> None:
    page = build()
    write(OUTPUT, page)
    seeded = seed_bugs_md()
    print(
        f"{OUTPUT.relative_to(ROOT)}: {len(plan_areas())} areas, {len(page) // 1024} KB"
        + (f"\n{BUGS.relative_to(ROOT)}: seeded" if seeded else "")
    )


if __name__ == "__main__":
    main()
