# Best Hours Implementation Guide · "Your best hours" + "Day by day"

> **Status: DEV READY, comp approved.** All design decisions settled 2026-07-25/26.
> The comp revision (C1/C5/C6 + caption/data consistency) was reviewed and signed
> off 2026-07-26; it is a faithful build reference. Only the Remote Config key
> strings remain, and those are named below.
>
> **Comp caption caveat:** the mock's afternoon "second wind" peaks at ~34% of the
> chart purely to illustrate the state. At runtime the C4 floor
> (`bh_second_wind_min` and the half-the-peak-share ratio) decides whether the
> second-wind clause appears; do not infer a qualifying threshold from the mock's
> bar heights.
> Design reference: Claude Design project `a29baf31-09f7-4a61-b4d3-afd8e0191c26`,
> `Best Hours Cards.dc.html` (states 1a card 1 · 1b card 2 full · 1c card 2 realistic mix ·
> 1d both in place · 1e exploratory calendar layer). **The comp is referenced, not
> embedded; open the Design project to view the rendered cards.**
> First item in the post-Personal-Layer discovery batch. Batch order:
> **1. Best Hours** → 2. Suggestions (weekday scope, re-time surfaces, push counting) →
> 3. Effort/duration → 4. Editor layout.
> (Calendar was the old item 4 and is now tabled: `calendar-decision-record.md`.)
> TestFlight was deliberately deferred to allow this batch.

---

## 1. Scope in one paragraph

Two new cards on **Streaks & stats** (`You/Stats/`) that replace the existing
"Your rhythm" four-band card. **Card 1 "Your best hours"** is a 24-bucket hourly
histogram of completion times with the best 3-hour window highlighted, a Mochi
commentary line, and two stat tiles. **Card 2 "Day by day"** is seven per-weekday
box plots (first-to-last range, middle-half capsule, typical dot) on the *same*
horizontal axis, so the two cards stack as a matched pair. Both read from
`CompletedTaskStat` fields that are already captured; **no model change, no
migration, no new permission, no Firestore rules change**. The weekday view is the
visible form of a new scope dimension that Feature 2 will add to the suggestion
engine.

---

## 2. Decisions locked

| # | Decision | Rationale |
|---|---|---|
| D1 | **Two cards, laddered by evidence.** Histogram shows whenever there is data; Day by day appears only when rows qualify. | A new user sees something. Per-weekday slicing needs ~7x the data. |
| D2 | **Recurring completions are EXCLUDED** from both cards. | A Monday 8am recurring chore would make Mondays the "peak" forever. Matches what `ObservationEngine.weekdayCandidate` already does. |
| D3 | **Axis runs 5a to 5a**, not 6a to 11p. | `TimeOfDayBand` already defines the day as starting at 05:00 (Morning = minute 300; Night wraps 21:00 → 05:00). A 2am completion lands at the far right reading as "late" instead of being clipped. |
| D4 | **Thin rows show the typical dot only.** No capsule, no range bar. | Honest about "we know roughly when, not how consistently," without looking broken. |
| D5 | **Row qualifies for a capsule at 5 completions across 3 distinct dates.** Both values Remote Config tunable. | Low enough to fill in within a month, high enough that a middle-half means something. |
| D6 | **"Day by day" is hidden on the Week range.** Shows on Month and 3 months only. | 7 days = at most 1 sample per row. A box plot of one point is a lie. |
| D7 | **Stats only. Nothing goes in the Journal.** | Journal follows record-not-grade (`JournalBehavior.swift:5-10`) and has no range picker. A "best hours" chart is a grade. |
| D8 | **The rhythm card's VIEW is deleted; `TimeOfDayBand` the type STAYS.** | `ObservationEngine` depends on the type. Only the UI retires. |
| D9 | **"busiest on Mondays" is dropped from the trend card caption.** | Superseded by Day by day, and it is computed wrong (see §5). User approved the removal. |
| D10 | **"In window %" reuses the suggestion engine's existing 180-minute window** (±90 around the peak). | Same definition means the number can never contradict the suggestion chip. |

### The calendar layer (state 1e) is TABLED

State 1e explores a calendar layer: a hatched overlay of recurring commitments, a
"Calendar on" chip in the header, and the right-hand label switching from the
typical time to "Free 10:30a" / "All clear".

**That feature was tabled on 2026-07-25. See `calendar-decision-record.md`.** In
short: recurring commitments are already a hole in the completion history, so the
hatch names a gap rather than revealing one. **Do not build state 1e.** It stays in
the design project as a record of the explored direction.

The layout should still not actively preclude it, since the record names two
triggers that would revive it, but no work should be spent making room.

---

## 3. What the comp proves (verified, not eyeballed)

The design comp is geometrically exact and can be built from directly:

- **Axis fractions are correct** for a 5a-to-5a (1440 min) span: 12p at 29.17%,
  6p at 54.17%, 11p at 75%.
- **All seven right-hand times match their dot positions to the minute.** Example:
  Mon's dot at 24.31% = 350 min past 5a = 10:50a, which is the printed label.
- **"In window 55%" is the true computed value** for the depicted histogram. The
  three highlighted bars sum to 261 of 472 total bar-height units = 55.3%.
- Everything is driven from flavor tokens (`--primary`, `--primary-soft`,
  `--primary-text`, `--accent2`, `--surface`, `--surface-2`, `--muted`, `--line`,
  `--ink`), with a 5-value flavor prop, so all five flavors hold.

---

## 4. Required changes before build

| # | Change | Why |
|---|---|---|
| C1 | **SETTLED: replace the "AVG. DONE" tile with "PEAK · 10a to 1p" (a range), paired with "IN WINDOW · 55%".** | An arithmetic mean is meaningless on a wrapped axis (the exact reason `circularCenterMinute` exists); the comp's 11:24a does not even match its own bars (true mean ≈12:55p). The range form was chosen over a single "Typical" circular-median time: peak-range + in-window is the same fact stated two ways, both computed from the ±90 window (D10), so no circular-median path is needed on this card. Both tiles kept. |
| C2 | ~~**Minimum hatch width, or drop short commitments.**~~ **VOID** while the calendar layer is tabled (`calendar-decision-record.md`). Recorded only so it is not rediscovered: in 1e a 30-minute meeting is 2.08% of the axis ≈ 5px on a 352px card, and a 5px box with a 1px border and a 2px/3px repeating gradient renders as a gray smudge, not a hatch. | No hatch is being built, so nothing to fix. |
| C3 | **The Mochi caption is conditional on chart state, not a static pool.** | 1c's line names *which* days are thin ("Thursday and the weekend are still quiet..."). The existing copy system is pool-based with FNV-1a rotation against archived line ids. This caption needs a different shape. |
| C4 | **The secondary-window claim needs its own evidence floor.** | 1a's copy says "a small second wind shows up around 8p" for a bump that is under 3% of completions. Without a floor, Mochi will confidently narrate noise. |
| C5 | **1d highlights the wrong tab** (Journal). Streaks & stats is reached from **You**. | Mock error; do not copy into the build. |
| C6 | **Drop "First to last" from the legend.** | Three legend items wrap to two lines at 320pt. A thin line between two ends reads as a range without being labelled. |
| C7 | **Contrast-check `--primary-text` on `--surface-2` in all five flavors.** | Carries the "In window" value and "All clear". The comp only proves Black Sesame. |

### Known accepted cost

The 5a-to-5a axis (D3) leaves roughly the right quarter of both cards empty for a
normal-schedule user. Accepted deliberately: a dynamic axis would break the match
between the two cards and make one month incomparable to the next.

**Screen length (SETTLED): accepted, both cards stay inline, no collapse.** The two
cards add ~600px to an already-long screen, but they are self-gating: the histogram
shows only with data, and Day by day only when rows qualify and never on the Week
range (D1, D6). A new or light user never sees the long form, and someone who does
has enough history to want it. A default-collapse disclosure was rejected: it would
introduce the one expand/collapse component the app deliberately lacks, for a single
card. This screen was rebuilt to be rich on purpose.

---

## 4b. The caption (C3/C4 resolved)

The Mochi commentary line is generated from chart state, not drawn from a static
rotation pool. Four states, in priority order, all in the pet's voice, all
qualitative (no percentages, per `mochi-copy-style`):

| State | Condition | Line |
|---|---|---|
| Second wind | a secondary window clears its floor (below) | "You get the most done in the {peakBand}, with a smaller second wind in the {secondaryBand}. {name} sees it." |
| Thin days | Day by day qualifies but ≥1 weekday row is still thin (below D5) | "{name} has a good read on your week. {thinDays} are still quiet." |
| Full read | Day by day qualifies and every row has a capsule | "You get the most done in the {peakBand}. {name} sees the pattern." |
| Learning | histogram only; Day by day not yet earned | "Still learning your week. Here's your day so far." |

- **`{peakBand}` / `{secondaryBand}`** are `TimeOfDayBand` names (morning / afternoon
  / evening / night), never clock times, so the line reads warm and never contradicts
  the tiles.
- **`{thinDays}`** is a natural-language join of the sub-floor weekday names
  ("Thursday and the weekend"), with a weekend fold when Sat+Sun are both thin.
- **C4 secondary-window floor:** name a second wind only when its own window holds
  **≥ `bh_second_wind_min` completions across ≥ `bh_second_wind_dates` dates AND its
  share is ≥ half the peak window's share.** The comp's "8p second wind" at under 3%
  of completions would fail this and be dropped, which is the point: without the
  floor Mochi narrates noise.
- These are generated lines, so there is **no FNV-1a rotation** here (that system is
  for static pools). The state itself is the variety.

---

## 5. What exists vs. what must be built

Already in place and reused:

| Rail | Where | Reused for |
|---|---|---|
| Local completion context | `CompletedTaskStat.completedLocalDate` / `completedLocalMinute` / `completionTimeZone` / `localContextDerived` (`Tasks/TaskRepository.swift:18-77`) | every bucket and every row, in the zone where the completion happened |
| Recurring flag | `CompletedTaskStat.isRecurring` (`:42`) | the D2 exclusion filter |
| Day boundary | `TimeOfDayBand` (`Observations/ObservationTypes.swift:26-39`) | the 5a axis origin (D3) |
| Circular time math | `DistributionResult.circularCenterMinute` (`Observations/ObservationTypes.swift`) | typical time / circular median, never a naive mean |
| Peak window width | `SuggestionConstants.peakWindowMin` (±90) | the highlighted 3-hour run and "In window %" (D10) |
| Per-day contribution cap | `ObservationConstants.dayCap = 3` (`:26`) | stop one heroic day reshaping a row |
| Range picker + fetch cache | `StatsBehavior.TimeRange` (`:17-49`, 7/28/91 days, default `.month` at `:95`), `StatsViewModel.statsCache` (`:29, 88-93`) | both cards follow the picker; toggling ranges does not re-hit Firestore |
| Card chrome | existing Stats cards (`You/Stats/StatsView.swift`), `MochiRadius`, eyebrow header style | visual consistency, no new components |
| Conditional card omission | `StatsView.swift:41-59` | D1 ladder and D6 hiding |

Must be built:

- A pure derivation layer over `[CompletedTaskStat]`: hourly bucketing on the 5a
  origin, best-3-hour-window scan, in-window share, per-weekday quartiles with
  circular handling, and per-row qualification against the D5 floors.
- Two SwiftUI cards in `You/Stats/`, plus deletion of `rhythmCard` / `bandBars` /
  `rhythmCaption` and the busiest-weekday half of the trend caption (D9).
- A state-aware caption generator (C3) with its own floors (C4).
- New Remote Config keys for the D5 row floors. **Current pin is 74 keys; this
  raises it.** Console publish is user-owned.
- Tests in `StatsViewModelTests.swift`. Note the existing gotcha: Stats/Journal
  fixtures anchor to the REAL clock (`liveNow`/`liveDay` helpers), not `Dates.now`.

---

## 6. Bug found in passing

`StatsViewModel.busiestWeekday` (`:243-253`) takes the weekday from
`calendar.component(.weekday, from: stat.completedAt)` using the **device's current**
calendar, rather than the stored `completedLocalDate` / `completionTimeZone` like
every other card. After travelling across timezones it disagrees with the rhythm
bands. It is also ungated (no evidence floor), which is why the Journal deliberately
refused to carry it (`JournalTimeline.swift:14-19`). D9 removes the only surface that
consumes it, so this dies with the caption rather than needing a separate fix.

---

## 7. Status of former open items

- [x] **Stat tile (C1):** PEAK range + In window. Settled (§4, C1).
- [x] **Caption pool and conditional structure (C3/C4):** settled (§4b).
- [x] **Screen length:** accepted inline, no collapse (§4 Known accepted cost).
- [x] **Remote Config keys (finalized):**
      - `bh_row_min` = 5 — D5 completions for a weekday capsule
      - `bh_row_dates` = 3 — D5 distinct dates for a weekday capsule
      - `bh_second_wind_min` = 5 — C4 completions inside the secondary window
      - `bh_second_wind_dates` = 3 — C4 distinct dates for the secondary window

      The C4 "share ≥ half the peak window's share" ratio (0.5) stays a **code
      constant**, not a key, to hold the count at four. All four are `number(...)`
      keys added to `numberKeys` for the startup audit. **Adds 4 to the 74 pin → 78.**
- [x] **Design comp revision** (C1 tiles, C5 correct tab, C6 legend) plus a
      caption/data consistency pass. Reviewed and approved 2026-07-26. The comp is
      now a faithful reference for all four states.

---

## 8. Implementation status and human test cases

**Built 2026-07-27** (commit "Replace the rhythm card with Best Hours and Day by day cards").
Derivations, cards, caption states, D9 caption trim, and the four bh_* keys are in
code with unit coverage in `StatsViewModelTests.swift` (histogram, weekday rows,
caption states, RC resolution). The items below need a human.

### Console (blocking for tuned floors, not for shipping defaults)

- [ ] Publish `bh_row_min` = 5, `bh_row_dates` = 3, `bh_second_wind_min` = 5,
      `bh_second_wind_dates` = 3 in the Firebase console. The whole discovery
      batch moves the pin 74 → 84; after publishing all ten new keys, launch a
      DEBUG build and confirm the startup audit logs
      `remote_tuning_audit all 84 keys remote-sourced`.

### Visual, against the approved comp (Best Hours Cards.dc.html)

- [ ] Both cards in all five flavors. Especially C7: the In window value and any
      `--primary-text`-on-`--surface-2` text must pass contrast outside Black Sesame.
- [ ] The two cards stack as a matched pair: the 12p / 6p / 11p ticks align
      between the histogram and the Day by day rows.
- [ ] 320pt-wide device (SE class): tiles do not wrap, the legend stays on one
      line (C6 dropped "First to last" for exactly this).
- [ ] A normal-schedule account: the right quarter of both cards is empty and
      reads as intended (the 5a-to-5a axis, accepted cost in §4).

### Behavior with real data

- [ ] Week range hides Day by day even when Month shows it (D6).
- [ ] A fresh account shows neither card; after one completion the histogram
      appears alone (D1 ladder).
- [ ] A recurring daily chore does NOT drag the peak (D2) but a burst of one-off
      completions does.
- [ ] Caption sanity: the second-wind clause only appears when the secondary
      window is real (C4); the thin-days line names the actually-quiet days and
      folds Sat+Sun into "the weekend".
- [ ] After changing the device timezone, buckets stay put (completions render
      in the zone where they happened, not the current one).

### Accessibility

- [ ] VoiceOver on the histogram reads the peak range and in-window share as one
      summary element; each Day by day row reads its typical time or "still quiet".

---

## 9. Day picker (comp turn 3, built 2026-07-27)

State 3a added a picker to **Day by day**: a pill under the eyebrow ("All
days" / a weekday) plus tappable rows. Picking a day swaps the card's middle
for that day's own 24-bucket hour curve on the shared 5a axis with day-scoped
Peak / In-window mini tiles; the divider and Mochi line stay. As-built
decisions (settled with the user 2026-07-27):

- **Pickable = any day with data.** Bars render whatever the slice holds -
  bars show, they don't claim - but the tiles and the peak highlight wait for
  the row's existing D5 floor, so two data points can never mint "100% in
  window". A day with zero completions is not offered and a stray pick lands
  back on All days.
- **Day captions** (two states, generated like C3): qualified -
  "{Weekday}s usually come together in the {band}. {name} has been watching." /
  thin - "Still learning your {weekday}s. Here's what {name} has so far."
  Distinct verbs from both the pooled observation voice and the suggestion
  chip's weekday phrasing.
- **Card 1 stays pooled** - the selection is scoped to Day by day, per the
  comp's "only the middle changes".
- The pill is a native Menu behind the comp's capsule look (the EFFORT pill
  recipe). Selection is view-state only: reset on screen entry and range
  change, never persisted, no new Remote Config keys.

### Human test cases

- [ ] Pill and dropdown across all five flavors against 3a; chevron in
      primary-text, selected row treatment in the menu.
- [ ] Tap a rich row and a thin row: both open the day view; the thin day
      shows bars + learning caption with NO tiles and no highlight.
- [ ] "All days" returns to the seven rows with the axis unchanged - the eye
      test from the comp note: the single day reads against the memory of the
      stack.
- [ ] Range toggle while a day is selected returns to All days.
- [ ] VoiceOver: the pill announces "Day filter: ...", rows hint "Shows this
      day's hours", the day chart reads its peak and share (or "still
      learning").

---

## 10. Header, marks, and the chart explainer (user pass, 2026-07-27)

Post-comp refinements requested after living with the cards:

- **Stacked headers on both cards**: eyebrow, window label left-aligned
  beneath it (no more inline "· Last 4 weeks"), and a `questionmark.circle`
  on the trailing edge.
- **Larger Day by day marks**: middle-half capsule and typical dot 9 → 12pt
  (rows 16 → 18pt tall), legend swatches to match. The 5pt still-learning dot
  deliberately stays small. The first-to-last span line thickens slightly
  (2 → 2.5pt) but remains unlabeled in the legend (C6 stands).
- **`BestHoursHelpView`** (`You/Stats/`, pushed via
  `YouRouting.navigateToBestHoursHelp`, route key `you.stats.help`): a
  general explainer in the pet's voice - the histogram and its two tiles, the
  5a-to-5a clock, the Day by day anatomy with live swatches (including the
  span line C6 left unlabeled, and the noon/6p gridlines), and what counts
  (recurring exclusion, evidence patience, completion-zone dating). No
  user-specific numbers; the cards carry those.

### Human test cases

- [ ] Help screen renders in all five flavors; swatches match the real card
      marks; back returns to Stats with state intact (range + day selection).
- [ ] The "?" is reachable from both cards and comfortably tappable.
- [ ] Larger marks: rows still clear the noon/6p gridlines and nothing clips
      at 320pt.
- [ ] VoiceOver: "About these charts" on the button; each legend row on the
      help screen reads title and description as one element.
