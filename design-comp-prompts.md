# Claude Design prompts · discovery batch comps

> Paste-ready prompts for the three comps the batch still needs, written 2026-07-26.
> They share MochiBuddy's flavor-token system so the outputs match the existing
> `Best Hours Cards.dc.html` in project `a29baf31-09f7-4a61-b4d3-afd8e0191c26`.
>
> **Shared design system (all three assume this):**
> - Five flavors via one flavor prop: Black Sesame, Strawberry, Matcha, Ube, Mango.
> - CSS custom properties only, never hard-coded colors: `--primary`,
>   `--primary-soft`, `--primary-text`, `--accent2`, `--surface`, `--surface-2`,
>   `--muted`, `--line`, `--ink`.
> - Card chrome: rounded corners (~20px), an eyebrow header (small uppercase muted
>   label), matching the existing Stats cards.
> - Mobile: ~352px card on a 390px screen.
> - Copy rules: no em dashes anywhere, no emoji. Glyphs are SF Symbols (name them).
>   En dash "–" for empty values, "·" for subtitle separators.

---

## 1. Best Hours cards — revision of the existing comp

> Update the existing "Best Hours Cards" comp. Keep states 1a-1d and the 5a-to-5a
> axis, the highlighted 3-hour peak window, and the per-weekday box plots. Make
> exactly these changes:
>
> 1. **Replace the "AVG. DONE 11:24a" stat tile** with two tiles side by side:
>    **"PEAK · 10a to 1p"** (a time range) and **"IN WINDOW · 55%"**. Same eyebrow
>    style as the other tiles. These are the same fact stated two ways.
> 2. **Fix the tab highlight in the "both cards in place" state:** the active tab is
>    **You**, not Journal. Streaks & stats is reached from You.
> 3. **Drop the "First to last" item from the box-plot legend.** Keep only the
>    middle-half capsule and the typical dot. Two legend items, one line.
> 4. **Remove the exploratory calendar layer (the hatched overlay / "Calendar on"
>    chip) entirely.** That direction is tabled; do not show it.
> 5. **Show the Mochi caption in its four states**, one per variant, qualitative
>    with no percentages:
>    - "You get the most done in the evening, with a smaller second wind in the
>      afternoon. Nori sees it."
>    - "Nori has a good read on your week. Thursday and the weekend are still quiet."
>    - "You get the most done in the evening. Nori sees the pattern."
>    - "Still learning your week. Here's your day so far."
>
> Render all five flavors. Verify `--primary-text` stays legible on `--surface-2`
> where it carries the "IN WINDOW" value.

---

## 2. Re-time row badge — new comp

> Design a passive suggestion badge on a task row for MochiBuddy's Tasks tab and
> list-detail screens.
>
> - A task row (real component: `TodoItemRow`) carries, left to right: a completion
>   checkbox, the task title, and on the right a due time (e.g. "9:00 PM"), a small
>   list color dot, and a trailing priority chip ("High"/"Focus"/"Soon"). Head the
>   card with a list name, NOT "Today" (that is the Home surface, which is excluded).
> - **Add a soft badge** (SF Symbol **`clock.arrow.circlepath`** — clock with a cyclic
>   arrow, reading "adjust the time") in the accent tint (`--primary-text`), placed
>   just left of the due time so it reads as a gentle signpost, not an alert. It is
>   **icon only, never a time as text**. Not a warning triangle, not a red dot. Mochi
>   never scolds. (Do NOT use a plain clock: the real row already shows a `clock.fill`
>   for the due state.)
> - Show three rows stacked: one **with** the badge, one **without**, and one with a
>   **long title** to prove the badge never collides with or truncates the title or
>   the due time.
> - The badge means "Mochi has a re-time suggestion for this recurring task"; tapping
>   the row (not the badge) opens the editor. Show it as a non-interactive-looking
>   accent glyph.
>
> Render all five flavors. Keep the row height and existing right-side elements
> unchanged; the badge must fit the current row, adding no height.

---

## 3. Effort pill and menu — new comp (revised 2026-07-26)

> Revision note: the first pass hung an unlabeled "Snack" pill off the Priority
> eyebrow and it read as a random quirky word — nobody could tell what was being
> estimated. Fix: give the control its own "EFFORT" label and use plain magnitude
> levels. Labels changed from the food set to Tiny/Small/Medium/Large.
>
> Design an effort control for MochiBuddy's task editor, sharing one row with
> Priority as two clearly-labeled questions.
>
> - **Left, the Priority block:** an eyebrow label "PRIORITY" over three chip choices
>   Low / Med / High, one selected (filled with `--primary`, text `--primary-ink`),
>   the others `--surface` with a `--line` stroke.
> - **Right, the Effort block:** its own eyebrow label "EFFORT" over a single compact
>   pill using the date/time pill recipe (surface fill, `--line` stroke, rounded,
>   small chevron). It is a pill, NOT a chip ladder, so it never mirrors the Priority
>   chips. Show two states:
>   - **unset:** the pill reads "Set effort" in the muted style (`--muted`).
>   - **set:** the pill reads "Medium".
> - Show the **open menu** (tapped state) as a popover listing four options
>   **Tiny · Small · Medium · Large** (ascending) plus a **Clear** row, current
>   selection checked. A short "Effort" header is fine. No clock times anywhere.
> - The point of the layout: PRIORITY (Low/Med/High) and EFFORT (Tiny/Small/Medium/
>   Large) are two labeled questions of different shape, never a duplicated scale.
>
> Render all five flavors. The pill must not wrap; the longest label is "Medium".
