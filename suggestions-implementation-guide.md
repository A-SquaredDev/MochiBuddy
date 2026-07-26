# Suggestions Implementation Guide · Weekday scope · Row badge · Push counting

> **Status: DEV READY, comp approved.** All decisions settled 2026-07-25/26. The
> re-time row-badge comp was built and signed off 2026-07-26 (`Suggestion Badge.dc.html`).
> Copy is drafted (§7); no open design questions remain.
> Second item in the post-Personal-Layer discovery batch. Batch order:
> 1. Best Hours (`best-hours-implementation-guide.md`) → **2. Suggestions** →
> 3. Effort/duration → 4. Editor layout.
> (Calendar was the old item 4 and is now tabled: `calendar-decision-record.md`.)
> Builds on the shipped v0.7 Feature 5 module (`MochiBuddy/Suggestions/`,
> `feature5-implementation-guide.md`).

---

## 1. Scope in one paragraph

Three independent changes to the existing suggestion machinery. **(A)** A weekday
filter that is tried only as a *fallback* when the pooled distribution is silenced
by the bimodal runner-up gate, which reaches a class of user the engine is currently
structurally incapable of serving. **(B)** A passive clock badge on task rows that
signposts an available re-time suggestion, because the chip already works and the
real failure is that nobody knows it exists. **(C)** Repairing `rescheduleCount`,
which today only increments on snooze and is unreadable on live tasks, so the
"you keep pushing this" case is invisible to the entire app. No new permission, no
Firestore rules change. A and B are independent of each other (see §5).

---

## 2. Decisions locked

### A. Weekday as a fallback on silence

| # | Decision | Rationale |
|---|---|---|
| A1 | **Weekday is a fallback, not a tier.** Only retried after the pooled answer is silenced by the runner-up-margin gate (`SuggestionEngine.swift:333-338`). | Zero regression risk. Nothing that qualifies today changes. |
| A2 | **Fallback applies at list and global scope only. Never series.** | `ObservationConstants.windowDays = 42` holds at most **6** of any given weekday. The series floor is 8 completions across 5 dates (`SuggestionConstants.swift:31,33`) and is therefore unreachable under a weekday filter. |
| A3 | **Weekday-filtered scopes get their own, lower floors.** New Remote Config keys. | A weekday slice has roughly 1/7 the evidence. Reusing the pooled floors would make the fallback never fire. |
| A4 | **Provenance must be recorded.** `DistributionResult.Scope` / `SuggestionScopeTier` need to express "list, this weekday" and "global, this weekday". | `SuggestionCopy` is tier-typed so global can never wear list phrasing. A weekday-scoped answer needs its own phrasing and must not borrow the pooled voice. |

**The user this unlocks:** someone who does a chore at 8am on weekdays and 2pm on
weekends has a textbook bimodal history. The runner-up gate silences them, working
exactly as designed, and no amount of additional data will ever change that. The
fallback is the only path that reaches them.

### B. Re-time row badge

| # | Decision | Rationale |
|---|---|---|
| B1 | **A badge, not an action.** Tapping the row does what it always did: opens the editor, where the existing chip explains and offers the time. | The problem is discoverability, not capability. No new navigation, no new tap target, no new interaction to design. |
| B2 | **`clock.arrow.circlepath` glyph in the accent tint. Not a warning triangle, not a red dot.** | Mochi never scolds. **Revised from a plain clock 2026-07-26:** the real row (`TodoItemRow.swift:105-109`) already shows a `clock.fill` when a task is `.due`, so a second plain clock would collide. `clock.arrow.circlepath` (clock + cyclic arrow) reads "adjust the time," is on-message for re-time, and is visually distinct from the due clock even when both appear on one row. SF Symbol per `mochi-copy-style`. |
| B3 | **Icon only. Never the suggested time as text.** | Rows already carry title, due time, list dot, priority dot. "usually 9:20p" competes directly with the real due time inches away, and truncates or wraps on long titles. |
| B4 | **Evaluated once per fetch and cached with the list. Never per row render.** | Tasks and ListDetail both render rows. The engine is pure over already-fetched stats (CPU, not network), but a naive implementation re-evaluates the gate for every recurring timed task on every render. |
| B5 | **Re-time only. Not new-time.** | A "Mochi suggests a time" badge on every undated task would be noise. |
| B6 | **The badge appears on the Tasks tab and ListDetail only. NOT on Home's today list.** | Home rows are the most space-constrained, and Home is a today view while re-time is about a recurring series' habitual time. Discovery still happens wherever people browse their tasks; tapping a Home row still opens the editor with the chip. **Mechanism (see "Where the badge attaches" below):** `TodoItemRow` is a single shared component, so B6 is enforced by a caller-supplied flag, not by the row itself. |

### B-impl. Where the badge attaches (real code, not the comp's mock row)

The comp (`Suggestion Badge.dc.html`) invented its own task row. The real row is a
**single shared `TodoItemRow`** (`CommonUI/DesignSystem/TodoItemRow.swift:22`), called
by all three surfaces: Home (`HomeView.swift:570`), Tasks (`TasksView.swift:201`),
ListDetail (`ListDetailView.swift:129`). Build against this, not the mock.

| Fact | Where | Consequence |
|---|---|---|
| Trailing meta `HStack(spacing: 4)` | `TodoItemRow.swift:104-129` | the badge's home |
| Due time is baked into `Text(meta)` (e.g. "Fri · 9:00 AM"), not a standalone view | string at `TodoItemDisplay.swift:52`, rendered `TodoItemRow.swift:110-114` | **insert the badge immediately after `Text(meta)` (after line 114), before the list-dot block at :115** |
| An existing conditional `clock.fill` already sits in this HStack for `state == .due` | `TodoItemRow.swift:105-109` | the reason B2's glyph moved to `clock.arrow.circlepath` |
| Priority is a trailing **chip** ("High"/"Focus"/"Soon"/"Done"), not a dot | `TodoItemRow.swift:134-140`, text at `TodoItemDisplay.swift:81-85` | the comp's "priority dot" was fictional; badge placement is unaffected |
| List color dot = `Circle().fill(listColor ?? theme.muted)` 7pt | `TodoItemRow.swift:121-123` | badge sits left of the "·" + dot |
| The row is **shared with Home and with Apple Reminders rows** (Reminders flagged by `sourceBadge == "Reminders"`, `TodoItemRow.swift:31`) | callers 1a-1c above; reminders set at `TasksViewModel.swift:485`, `ListDetailViewModel.swift:251` | **B6 + Reminders exclusion are enforced by a new flag**, not by the row |

**The gating flag (enforces B4/B6 and the Reminders exclusion):** add a
`showsRetimeBadge: Bool` to the Tasks and ListDetail row-item models
(`TasksBehavior.TodoUIItem`, ListDetail's item) — **not** Home's
(`HomeBehavior.TodoUIItem`). Compute it once per fetch (B4) from the cached
suggestion evaluation, force it false when `sourceBadge == "Reminders"`, and pass it
into `TodoItemRow`. Home never sets it, so the badge can never appear there.

### C. Push counting

| # | Decision | Rationale |
|---|---|---|
| C1 | **Increment on any user move of an incomplete task's due date to a LATER date.** Adds the editor date-edit path (`updateTask`, `TaskRepository.swift:207-220`) to the two snooze paths that already count. | The editor is how most people actually push a task, and it currently counts nothing. |
| C2 | **Do NOT increment on:** moving a date earlier, skip-occurrence (`TaskEditorViewModel.swift:179-186`), vacation triage reschedule (`HomeViewModel.swift:229-244`), or `RecurrenceRoller` auto-advance. | Different intents. The roller already has its own `missedCount`. Triage is a bulk system-offered action. |
| C3 | **Parse `rescheduleCount` in `taskItem(id:data:)`** (`TaskRepository.swift:301-316`) and add it to `TaskItem` (`Tasks/TaskItem.swift:98-117`). | Today it is write-only. The only reader is the completed-stats query, which filters on `completedAt` (`:362-364`), so a task pushed five times and never finished is invisible to the entire app. |
| C4 | **Do this first, regardless of when anything consumes it.** | The only time-sensitive item in the whole discovery batch. Push history cannot be reconstructed retroactively. |

---

## 3. What exists and is reused

| Rail | Where | Note |
|---|---|---|
| Scope enum | `ObservationEngine.SuggestionScope` (`:203-207`): `.series` / `.list` / `.global` | extended with weekday-filtered variants |
| Precedence | applied by the caller (`SuggestionEngine.swift:71-88`); **no fallback inside** `suggestionDistribution` (`ObservationEngine.swift:199-202`) | the fallback belongs at the caller, consistent with the existing split |
| Qualification | `qualify(_:floors:)` (`SuggestionEngine.swift:241-365`), raw day-capped counts, 3/day cap | weekday variants pass different floors, same function |
| The bimodal gate | runner-up margin 0.10 over the best window ≥3h away (`:333-338`) | the trigger for the fallback |
| Re-time evaluation | `evaluateReTime` (`:106-156`), series-only, timed-only, saved-only, ≥3h mismatch (`retimeMismatchHours`, `SuggestionConstants.swift:41`) | unchanged; the badge only surfaces its result |
| Guardrails | `guarded` (`:160-194`): bedtime, 30-min lead, 60-min dismiss re-arm | unchanged, still applied after the fallback |
| Ledger | `SuggestionLedger` at `mochi.suggestions.ledger.<uid>`, trigger-keyed dismissals on the displayed minute | weekday-scoped proposals must key consistently |
| Weekday derivation | `CivilDay.weekday` (`ObservationEngine.swift:88-90`) | exists, currently only consumed by `weekdayCandidate` |
| Reschedule weight | `1 + min(count,3) * 0.25` (`SuggestionEngine.swift:348-352`), peak-shaping only, post-qualification | benefits automatically from C1's better data |
| DEBUG inspector | `DevSuggestionsInspector.swift` (task picker, both triggers gate-by-gate, ledger dump) | extend to show the fallback path and the weekday floors |

**Must be built:** weekday-filtered scope variants and their floors, the fallback
branch at the caller, weekday-aware copy tiers, the row badge plus its per-fetch
cache across three row surfaces, the C1/C3 repository changes, new Remote Config
keys (**current pin is 74; A3 raises it**), tests.

---

## 4. Gotchas carried forward from Feature 5

- iOS time formatting uses **U+202F** (narrow no-break space) before AM/PM. Pin
  expected strings with `\u{202F}`.
- Editor-VM suggestion tests must anchor fixture dates to the **real clock**
  (`liveDay` helper), not `Dates.now`, and put due dates tomorrow so the lead-time
  guard cannot race the suite.
- `#expect(x.contains(where: \.keyPath))` and `allSatisfy(\.keyPath)` both break the
  Swift Testing macro. Bind or use a closure.
- Apple Reminders rows never open the editor, and are excluded from suggestions by
  `isAppleSource`. The badge must respect the same exclusion.

---

## 5. Expectation-setting: A and B do not compound

**The weekday fallback will not make the row badge appear more often.** Weekday
filtering is viable only at list and global scope (A2); re-timing is series-scoped
with no fallback. So:

- **A** improves *new-time* suggestions, the editor chip when picking a time.
- **B** improves discovery of *re-time* suggestions, which fire at exactly today's rate.

Two different halves of the engine. The badge should not be judged against a lift it
was never going to receive.

---

## 6. Related dead code found in passing

`missedCount` and `lastMissedAt` are written by `RecurrenceRoller.rollForwardTask`
(`TaskRepository.swift:230-237`, deliberate per the comment at `:105-108`) and are
**never read anywhere in the app**. Not in scope here, but they are the natural
signal for a future "this recurring task keeps getting missed" feature, and they are
already accruing correctly.

---

## 7. Copy (A4) and status of former open items

### Weekday-scoped chip copy (A4), settled

The weekday fallback needs its own reason lines so a weekday-scoped answer never
borrows the pooled voice. Distinguishable from the pooled tiers by naming the day
and using a distinct verb, without the clumsy "on Tuesdays you usually...":

| Scope | Line |
|---|---|
| weekday + list | "On {weekday}s, {list} usually gets done in the {band}." |
| weekday + list, name gone | "On {weekday}s you usually wrap up in the {band}." |
| weekday + global | "On {weekday}s you usually wrap up in the {band}." |

- `{band}` is the `TimeOfDayBand` name, matching the pooled tiers' `bandPhrase`.
- The distinct verb "wrap up" (vs the pooled "finish things") keeps the weekday line
  audibly different, so a user who sees both over time does not hear a template.
- These are `SuggestionCopy` additions, tier-typed exactly like the existing tiers
  (`SuggestionCopy.swift:38-62`), so provenance stays a type, never a string (A4).

### Former open items

- [x] **Badge surface:** Tasks + ListDetail only, not Home (B6).
- [x] **Weekday copy (A4):** settled above.
- [x] **Remote Config keys (finalized):**
      - `suggest_weekday_min` = 4 — A3 completions for a weekday-filtered scope
      - `suggest_weekday_dates` = 3 — A3 distinct dates for a weekday-filtered scope

      A 42-day window holds at most 6 of any weekday (A2), so the floor must sit below
      that; 4 across 3 dates is reachable yet meaningful. The weekday fallback
      **reuses the pooled `peakShare` (0.35) and `runnerUpMargin` (0.10)** rather than
      adding its own, so only two new keys. `number(...)` keys added to `numberKeys`.
      **Adds 2 to the 74 pin.**
- [x] **Design comp for the row badge.** Built and approved 2026-07-26
      (`Suggestion Badge.dc.html`, all five flavors): icon only, `--primary-text`
      tint, no fill or button chrome, long-title row truncates cleanly. Two comp
      caveats, both resolved in the doc rather than by a rebuild:
      - **Glyph:** change the plain clock to **`clock.arrow.circlepath`** (B2) — the
        real row already shows a `clock.fill` for the due state.
      - **Mock row is fictional:** build against `TodoItemRow` per "Where the badge attaches", not the
        comp's invented row (which also mislabeled the section "Today" = Home, and
        drew a priority dot the real row renders as a chip).
- [ ] **No consumer for `rescheduleCount` yet.** C is infrastructure and ships first
      regardless (C4); the "you have pushed this five times" surface is a later,
      separate decision, deliberately out of scope here.
