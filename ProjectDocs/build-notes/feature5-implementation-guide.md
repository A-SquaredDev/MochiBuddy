# Feature 5 Implementation Guide · Suggested Times

> Personal Layer build order: 1 → 4 → 3 → 2 → **5** → 6. Features 1, 4, 3, 2 are shipped.
> Spec: `mochi-requirements.md` § "Feature 5 — Suggested times" (lines ~2947–3227).
> This guide maps every spec requirement to concrete code, in the mandated architecture
> (DesignDocs: stores injected via `AppContainer`, pure domain functions, no singletons).

---

## 1. Scope in one paragraph

One editor-only suggestion chip, two triggers: **new time** (date set, no time chosen) and
**re-time** (a recurring Mochi series whose completions persistently land ≥ 3 circular hours
from its scheduled time). Suggestions come from the observation engine's `DistributionResult`
under **highest-qualifying-scope** precedence (series > list > global), qualify on **raw
day-capped counts** through four gates (evidence floor, peak share, peak-date spread,
runner-up margin), and render as a **friendly-rounded** half-hour time whose provenance copy
matches `scopeUsed` by construction. When unsure, no chip. Dismissal is once-until-changed
per trigger on the **rounded displayed** proposal; the chip lifecycle is session-frozen;
outcomes classify once at editor save. 14 new `suggest_*` Remote Config keys. This is the
Personal Layer's **actionability validator**.

## 2. What exists vs. what must be built (from codebase survey)

Already in place and reused verbatim:

| Rail | Where | Reused for |
|---|---|---|
| Distribution contract | `ObservationEngine.timeOfDayDistribution`, `DistributionResult` with `scopeUsed` (`ObservationTypes.swift`) | extended, not replaced (§3) |
| Circular minute math | `ObservationEngine.circularCenterMinute` | weighted variant for peak shaping |
| Day-capped sampling | `ObservationEngine.dayCappedMinutes` (stride-sampled, per `obs_day_cap`) | entry building for every scope |
| Civil-day currency | `CivilDay` (fixed UTC Gregorian, zone-honest) | date spread gates, ledger dates |
| 132-day stats fetch | `ObservationService.engineInputs(now:calendar:)` | suggestion inputs, **no new query** |
| Identity + reschedule provenance | `CompletedTaskStat.seriesId/taskId/rescheduleCount` (nil = unknown, never 0) | series scope, list concentration, weight bias |
| Bedtime window | `BedtimeWindow` (minutes-of-day, wraps midnight) on the profile | bedtime guardrail on the rounded time |
| Lapsed state | `MembershipSession.isLapsed` | the everything-asleep guard |
| Editor architecture | `TaskEditorViewModel` (`ObservableStateViewModel`, domain draft + `rebuild`) | chip state derivation |
| Chip placement | `TaskEditorView.whenBlock` (Date + Time field blocks) | inline row under the time controls |
| Per-UID device-local ledger pattern | `CallbackLedger` (UserDefaults JSON, own schemaVersion, cleared on deletion) | sibling `SuggestionLedger` |
| Telemetry pattern | `ObservationTelemetry` os_log protocol, coarse buckets, no payloads | `suggestion_*` events |
| Remote tuning pattern | `RemoteTuning` five-touch-point key pattern, count guard (60 today) | 14 `suggest_*` keys → 74 |
| Preallocation primitive | Firestore `collection.document()` mints ids without writing | dismissal survival on unsaved tasks |
| Dev tooling host | `DevSchedulerScreen` + `DevMemoriesInspector` pattern | DEBUG suggestions inspector |

Structural freebies discovered in survey:

- **Apple-sourced tasks never open the task editor** (`ListDetailViewModel.taskTapped`:
  "Reminder rows have no editor"). Edge case 10 is satisfied by construction; the engine
  still ingests their completions (they're in `completedTaskStats`), and `SuggestionEngine`
  keeps a defensive source guard + blocked reason anyway (cheap, future-proof).
- **Vacation needs no code**: no suggestion path consults vacation state, so "chips work
  normally" is the default. Pinned by a test, not by a branch.

Must be built: the entire `Suggestions/` module (qualification gates, window scan, weighted
peak, friendly rounding, scope precedence, guardrails, ledger, copy, service, telemetry),
the engine's series scope + per-entry provenance, editor session lifecycle + chip UI +
outcome classification, task-id preallocation, 14 tuning keys, the inspector.

## 3. Engine contract extension (the canonical statistical source stays canonical)

Feature 4 shipped `DistributionResult` as Feature 5's contract, but Feature 5's revised spec
needs three things the v0 shape lacks: a **series** scope, per-entry **dates** (peak-date
spread gate), and per-entry **identity + rescheduleCount** (list concentration guard, weight
bias). Extended in place — suggestions still come only from the engine:

```swift
// ObservationTypes.swift
struct DistributionResult: Equatable {
    enum Scope: Equatable {
        case series(String)      // NEW
        case list(String)
        case globalFallback
    }
    struct Entry: Equatable {    // NEW - one day-capped completion
        let minute: Int          // canonical minute-of-day, 0...1439
        let day: String          // completion-local civil date
        let identity: String     // seriesId ?? taskId
        let rescheduleCount: Int?  // nil = unknown (Apple), never "known unmoved"
    }
    let entries: [Entry]         // NEW - minutes/evidenceCount/distinctDates now derived
    let scopeUsed: Scope
    var minutes: [Int] { entries.map(\.minute) }
    var evidenceCount: Int { entries.count }
    var distinctDates: Int { Set(entries.map(\.day)).count }
}
```

```swift
// ObservationEngine.swift
enum SuggestionScope { case series(String), list(String), global }

/// Raw per-scope distribution for Feature 5. No fallback logic here -
/// scope precedence is Feature 5's qualification job, and a scope's
/// result honestly names itself. Series scope: TIMED completions only
/// (the spec's "8 timed completions" gate - a series' due-time is what
/// re-time proposes to change, so undated/date-only rows are not
/// evidence about it). Day capping runs AFTER scope filtering (the
/// Feature 4 order: a scope's cap is a fact about that scope's days).
static func suggestionDistribution(scope: SuggestionScope, inputs: Inputs) -> DistributionResult
```

The existing `timeOfDayDistribution(listId:inputs:)` keeps its Feature-4 fallback semantics
untouched; it now builds entries and derives the old fields (call sites unchanged).
`ObservationService` gains the matching passthrough
`suggestionDistribution(scope:now:calendar:)`.

## 4. New module: `MochiBuddy/Suggestions/`

Pure domain logic in enums of static functions (explicit `now`/`calendar`, zero clock
reads); one `@MainActor` service; one sibling ledger.

```
Suggestions/
├── SuggestionTypes.swift      // Trigger, ScopeTier, Proposal, gate checks, blocked reasons
├── SuggestionEngine.swift     // THE pure pipeline: gates → windows → weighted peak → rounding → guardrails
├── SuggestionConstants.swift  // the 14 remote-tunable values
├── SuggestionCopy.swift       // chip label / reason / confirmed / a11y strings, scope-locked
├── SuggestionLedger.swift     // per-UID dismissals + acceptance records (device-local, documented limitation)
├── SuggestionService.swift    // @MainActor: assembles a session context per editor open
└── SuggestionTelemetry.swift  // os_log events, no payloads
```

### 4.1 `SuggestionTypes`

```swift
enum SuggestionTrigger: String, CaseIterable { case newTime, reTime }
enum SuggestionScopeTier: String { case series, list, global }

/// Inspector + tests carry the gate story (ObservationGateCheck reused);
/// production accepts only a fully-formed proposal (candidate/qualified
/// split precedent, enforced at compile time).
struct SuggestionProposal: Equatable {
    let trigger: SuggestionTrigger
    let tier: SuggestionScopeTier
    let listId: String?          // tier == .list only (reason copy needs the name)
    let peakMinute: Int          // UNROUNDED - re-time mismatch measured on this
    let displayedMinute: Int     // rounded; ALL guardrails + ledger keys use this
    let band: TimeOfDayBand      // of displayedMinute - list/global reason copy
    let evidenceCount: Int
    let isRecurring: Bool
}

enum SuggestionBlockedReason: String {
    case noDate, hasTime, evidence, peakShare, runnerUp, peakDates,
         bedtime, leadTime, apple, lapsed, dismissed, mismatch, notSeries
}

struct SuggestionEvaluation: Equatable {
    let proposal: SuggestionProposal?
    let blocked: SuggestionBlockedReason?  // nil iff proposal != nil
    let gates: [ObservationGateCheck]      // inspector + tests
}
```

### 4.2 `SuggestionEngine` (pure): the whole pipeline

```swift
struct Context {                       // everything an evaluation reads
    let series: DistributionResult?    // scope .series, nil for tasks with no series identity
    let list: DistributionResult?      // scope .list, nil when the task has no list
    let global: DistributionResult     // scope .globalFallback
    let bedtime: BedtimeWindow
    let isLapsed: Bool
    let nowMinute: Int                 // caller-computed local minute (no clock reads)
    let today: String                  // caller-computed civil date
}

static func evaluateNewTime(task: TaskSnapshot, context: Context) -> SuggestionEvaluation
static func evaluateReTime(task: TaskSnapshot, context: Context) -> SuggestionEvaluation
```

Locked semantics, mapped:

- **Qualification (raw day-capped counts, weights never help).** A scope qualifies by
  passing ALL of: evidence ≥ floor (series `suggest_series_min` 8, else
  `suggest_min_evidence` 15) across ≥ distinct-date floor (series `suggest_series_dates` 5,
  else `suggest_min_dates` 5); primary-window share ≥ `suggest_peak_share` (0.35); primary
  window holds entries from ≥ `suggest_peak_dates` (3) distinct dates; primary share beats
  the runner-up window by ≥ `suggest_runner_up_margin` (0.10).
- **Window scan (deterministic).** Candidate centers = the 48 half-hours. A window is
  ± `suggest_peak_window_min` (90) circular minutes of its center, inclusive bounds. Primary
  = max raw count; count ties break to the **earliest center minute** (pinned here - the
  spec fixes determinism, not the tiebreak; earliest matches the "ties round earlier"
  temperament, and the margin gate kills any *real* tie anyway). Runner-up = best window
  whose center is ≥ 3 circular hours (180) from the primary center. Six-at-9am/six-at-6pm:
  both windows ≈ 0.40 share, margin 0 < 0.10 → silence, structurally.
- **List scope can't be one habit in a costume.** List additionally needs ≥
  `suggest_list_min_series` (3) distinct identities, and no identity > 
  `suggest_list_series_share` (0.40) of the list's day-capped entry count (the capped
  effective weight - raw, weights never help qualification). Fails → fall through to global.
- **Highest qualifying scope wins**: series, else list, else global - a scope wins only by
  passing its own gates, never by merely having rows. The proposal's tier IS the reason
  copy's tier (provenance can't be misstated by construction - `SuggestionCopy` takes the
  tier, not a string).
- **Peak (weights shape, never qualify).** Peak = weighted circular center of the primary
  window's entries; weight = `1 + min(rescheduleCount, 3) × suggest_reschedule_weight`
  (0.25, max 1.75×); `rescheduleCount == nil` → 1 (unknown, never "known unmoved").
  Unrounded peak feeds re-time's mismatch; only the proposal is rounded.
- **Friendly rounding (pinned).** Nearest half hour; exact quarter-hour ties (minute ≡ 15
  mod 30) round **earlier**; a round-up landing on 1440 would cross the task's date
  boundary → 23:30 instead (never next-day 00:00, never a fabricated shift). All guardrails
  evaluate the **rounded** minute.
- **Guardrail silences (never clamp):** rounded minute inside the bedtime window → silence;
  task due **today** and rounded minute < nowMinute + `suggest_min_lead_min` (30) →
  silence (same-civil-day comparison; a peak that already passed today is also a lead-time
  silence); `isLapsed` → silence before anything else; Apple source → silence (structural,
  see §2, guarded anyway). Every blocked case: chip simply absent.
- **Re-time eligibility:** recurring, `source == mochi`, has a due time, series identity
  exists, series scope passes its own gates, and circular distance between the *unrounded*
  series peak and the scheduled minute ≥ `suggest_retime_mismatch_hours` (3) × 60. Never on
  one-offs (no future series to change; **no title-based series inference** - identity is
  `seriesId ?? taskId`, titles are user content). Proposal = the series' own peak,
  friendly-rounded; applies series-forward through the normal recurring-edit save path.
- **Deterministic end to end**: every function is a pure function of (distributions, task,
  constants, explicit now/today/calendar); same inputs → same chip on any device.

### 4.3 `SuggestionLedger` (device-local, sibling of `CallbackLedger`)

Per-UID UserDefaults JSON under `mochi.suggestions.ledger.{uid}`, own `schemaVersion`,
cleared in the account-deletion path. Honestly per-device (spec-pinned, same class as
Features 2/4).

```swift
struct State: Codable, Equatable {
    var schemaVersion: Int
    /// "{trigger}|{id}" -> rounded displayed minute at dismissal.
    /// id = taskId (new-time; preallocated for unsaved tasks) or seriesId (re-time).
    var dismissed: [String: Int]
    /// Accepted suggestions awaiting the downstream retention check.
    var acceptances: [AcceptanceRecord]   // capped at 20, oldest dropped
}
struct AcceptanceRecord: Codable, Equatable {
    var trigger: String; var tier: String
    var taskId: String; var seriesId: String?
    var minute: Int                    // the accepted displayed minute
    var acceptedOn: String             // civil date
    var retentionReported: Bool
}
```

- **Once-until-changed, keyed by trigger:** a proposal is suppressed iff a `dismissed`
  entry exists for its exact trigger+id key AND the circular distance between the stored
  and current **displayed** minutes < `suggest_dismiss_rearm_min` (60). A 10:05 → 10:20
  internal drift that still displays "10:00" changed nothing; ≥ 60 displayed minutes
  re-arms. New-time dismissal never touches a re-time key (trigger-keyed isolation).
- Dismissal on a never-saved task uses the **preallocated** task id (§6.2), so it survives
  the save.

### 4.4 `SuggestionService` (@MainActor, injected via AppContainer)

```swift
struct SessionContext {   // frozen per editor open
    let engineContext: SuggestionEngine.Context  // minus per-evaluation task fields
    let ledgerState: SuggestionLedger.State
    let preallocatedTaskId: String?              // new tasks only
}
func beginSession(editingTask: TaskItem?, listId: String?, now: Date) async -> SessionContext?
```

- Assembles: `ObservationService.engineInputs` (the existing fetch, no new query) → the
  three scoped distributions via the engine; profile bedtime; `membershipSession.isLapsed`;
  ledger state; a preallocated task id when `editingTask == nil`. Returns nil signed-out.
- Re-computes the **list** distribution on demand when the user changes the task's list
  mid-session (`listDistribution(listId:)` over the cached inputs - the engine is pure, so
  re-scoping cached inputs is sound; no re-fetch).
- Owns telemetry emission + ledger writes: `recordShown`, `recordDismissed`,
  `classifyOutcome(atSave:)`, `recordEvaluated` (once per trigger per session where
  preconditions held - the session, not a day ledger, is the throttle).
- **Retention (the "did it actually help" signal), lazily at next session:** when
  `beginSession` sees an unreported `AcceptanceRecord` for this task/series (or the daily
  sweep in `engineInputs` completions can attest), it computes coarse buckets - accepted
  time survived unchanged into this edit? · did a subsequent completion of that task/series
  land within ± 90 circular minutes of the accepted time? · re-time reversed in this edit? -
  emits `suggestion_retention` (trigger + tier + coarse bucket only), marks reported.

### 4.5 `SuggestionCopy` (scope-locked, copy-style compliant)

No em dashes, no emoji, no percentages, no evidence talk. `{name}` = pet name, rendered at
display time. Times render via locale short style (`timeText(minute:calendar:locale:)`,
explicit locale for tests).

- New-time label: `"{name} suggests {time}."` · confirmed: `"{time} set"`
- Re-time label: `"This usually gets done around {time}."` · subtext:
  `"Tap to change its due time from here on."` (consent accuracy: says **due time**, says
  it persists; never "the reminder", never implies Mochi knows better - structurally
  asserted by test: re-time copy contains "due time", no copy contains "reminder").
- Reason lines by tier (the provenance principle, enforced by taking `SuggestionScopeTier`):
  series → `"This one usually happens around {time}."` · list →
  `"{ListName} things usually get done in the {band}."` · global →
  `"You usually finish things in the {band}."` Band words from `TimeOfDayBand` of the
  displayed minute ("morning" / "afternoon" / "evening" / "night" phrasing, night stays
  affirming per Feature 4's rule).
- Accessibility: chip = button, `"Set time to {time}. {name}'s suggestion: {reason}"`;
  dismiss = `"Dismiss suggestion"`.

## 5. Editor integration

### 5.1 Session lifecycle (session-frozen, one presentation per trigger)

`TaskEditorViewModel` holds `session: SuggestionService.SessionContext?` (fetched in
`.load`) plus `presented: [SuggestionTrigger: SuggestionProposal]` and
`chipStates: [SuggestionTrigger: ChipState]` (`offered` / `confirmed` / `dismissed` /
`removed`). On every `rebuild`:

- A trigger not yet presented re-evaluates against the **current draft** (date/time/list
  fields change preconditions); gates pass → present, freeze the proposal, record shown.
- A presented trigger never regenerates: the frozen proposal renders until a manual change
  removes its precondition (new-time: user picks a time manually → removed; if the manual
  time circular-matches within ± 30 the chip is *satisfied* - same removal, the outcome
  classifier tells them apart at save) or its lifecycle ends (tap / dismiss).
- Tap: sets `hasTime` + the displayed time into the draft exactly as a manual pick would
  (fully editable after), chip → quiet confirmed state. No scheduler work here - saving
  proceeds through the normal editor path; promise re-lay on save is the existing trigger.
- Dismiss: chip gone, ledger records trigger+id+displayed minute. No confirmation.
- Reopening the editor is a new session (new `beginSession`), subject to the ledger.
- At most one trigger's chip is visible at a time by construction (new-time needs no time,
  re-time needs a time), but both may present across one session (e.g. re-time shown, user
  clears the time, new-time presents) - each gets its own outcome at save.

### 5.2 Outcome classification (save-based, terminal)

Classified in the save paths (`performSave` / `saveDetachedOccurrence`) only - cancel,
delete, snooze record **no outcome** (an abandoned session is not evidence). Per presented
trigger, precedence at save: **tapped state > matched state > dismissed > ignored**:

- **accepted**: tapped, saved with the exact proposed time
- **adjusted**: tapped, changed, saved
- **matched**: never tapped; saved a manual time within ± 30 **circular** minutes of the
  displayed proposal (dismissed-then-matched resolves to matched - the save-time state
  outranks the earlier gesture)
- **dismissed**: dismissed and did not later match
- **ignored**: saved with none of the above
Accepted outcomes also append the ledger `AcceptanceRecord` (retention's input).

### 5.3 Chip UI (`TaskEditorView`)

Inline row directly under the Time field block inside `whenBlock` (present only with a
proposal - no placeholder, no layout jump, no badge; `MochiMotion.soft` transition rides
the existing animation). Anatomy: SF Symbol `clock` glyph · label · one-line reason
subtext · small `xmark` dismiss affordance. Tap = the whole row (a button); confirmed
state swaps to the quiet `"{time} set"` row. Dynamic Type wraps the reason line
(`fixedSize(horizontal: false, vertical: true)`), never truncates the time.

### 5.4 Construction sites

`TasksRouter.taskEditor`, `HomeRouter` quick-add, `YouRouter` (dev scheduler's editor) all
pass `container.suggestionService`. `AppContainer` builds `SuggestionLedger` +
`SuggestionService(authRepository:profileRepository:observationService:membershipSession:
ledger:telemetry:calendar:)`. `DeleteConfirmViewModel` clears the suggestion ledger
alongside the observation + callback ledgers.

### 5.5 Task-id preallocation

`TaskRepository` gains `allocateTaskId(userId:) -> String` (Firestore:
`tasks(userId).document().documentID` - mints an id, writes nothing) and `addTask` gains an
optional `id:` parameter (protocol-extension convenience keeps every existing call site
source-compatible; `FirestoreTaskRepository` writes via `document(id).setData` when given).
The editor VM preallocates at session start for unsaved tasks and saves through that id, so
a dismissal recorded against it survives the save. `StubTaskRepository` mirrors.

## 6. Remote Config (14 new keys · console publish required, user-owned)

| Key | Default | Clamp |
|---|---|---|
| `suggest_min_evidence` | 15 | 2...100 |
| `suggest_min_dates` | 5 | 1...50 |
| `suggest_peak_share` | 0.35 | 0...1 |
| `suggest_peak_window_min` | 90 | 15...360 |
| `suggest_peak_dates` | 3 | 1...50 |
| `suggest_runner_up_margin` | 0.10 | 0...1 |
| `suggest_series_min` | 8 | 2...100 |
| `suggest_series_dates` | 5 | 1...50 |
| `suggest_list_min_series` | 3 | 1...20 |
| `suggest_list_series_share` | 0.40 | 0...1 |
| `suggest_retime_mismatch_hours` | 3 | 1...12 |
| `suggest_min_lead_min` | 30 | 0...240 |
| `suggest_dismiss_rearm_min` | 60 | 0...720 |
| `suggest_reschedule_weight` | 0.25 | 0...2 |

Standard five-touch-point pattern: `ResolvedTuning` fields + `resolve` clamps + `numberKeys`
registration + `apply` into `SuggestionConstants` + `RemoteTuningTests` (count guard
60 → 74). **Console publish pending after this feature:** the 14 `suggest_*` keys join the
pending 24 `obs_*` + 6 `letter_*` + 6 `callback_*` (50 unpublished total). Shipped defaults
equal spec values, so behavior is correct without console action.

## 7. Instrumentation (os_log, no payloads ever)

What this validates, precisely: whether behavioral insights are **actionable** - not
whether the relationship layer is emotionally valuable. A dead global fallback means
"remove or redesign global fallback", nothing more.

- `suggestion_evaluated` - the denominator, once per trigger per editor session where the
  trigger's preconditions held: trigger + qualified + coarse blocked reason (evidence /
  peak share / runner-up / peak dates / bedtime / lead time / apple / lapsed / dismissed).
- `suggestion_shown`: trigger + scope tier + evidence bucket + recurring-vs-one-off.
- `suggestion_outcome`: trigger + tier + one of accepted / adjusted / matched / dismissed /
  ignored. Signal weights are an analysis-side fact, but **matched is always reported as
  its own component** (round times match by chance) - the event never blends them.
- `suggestion_retention`: trigger + tier + coarse bucket (survived / changed / reversed ·
  completed-in-window or not). Device-computed, no titles, ids, times, or lateness values.
- Stratification (trigger, tier, evidence bucket, recurring) rides the event fields;
  re-time has no global control group - absolute acceptance + retention only.

## 8. Dev tooling

DEBUG `DevSuggestionsInspector` section in the DevScheduler tab (DevMemoriesInspector
pattern): pick any incomplete task → both triggers' gate-by-gate story (per-scope evidence,
window scan winner + runner-up, unrounded peak vs displayed proposal, blocked reason),
ledger dump (dismissals with stored minutes, acceptance records), sharing the existing
time-travel cursor via cached inputs.

## 9. Test plan (spec "Test coverage (required)" mapped)

New files in `MochiBuddyTests` (Swift Testing, `Dates.now` anchor, constants pinned by
fixture construction):

| Spec bullet | Test file / cases |
|---|---|
| Gates table-driven: raw-count qualification (weights excluded), distinct dates, day cap, peak share, peak-date spread, runner-up margin with the 3h-separated scan, boundary-exact values, bimodal 6/6/3 → silence | `SuggestionEngineTests` |
| Circular math: cross-midnight peak, rounding (nearest half hour, quarter ties earlier, 23:45 → 23:30 boundary), re-time distance on the unrounded peak (21:00 vs 09:00 wrap) | `SuggestionEngineTests` |
| Scope: highest-*qualifying* precedence (rich-but-unqualified series loses to qualified list/global); list concentration guard (identity floor + 40% share) falls through to global | `SuggestionEngineTests` |
| Provenance copy: tier ↔ reason mapping table-driven; a global result can never render series/list phrasing; re-time copy says "due time", nothing says "reminder"; no digits beyond the time, no em dash, no emoji | `SuggestionCopyTests` |
| Guardrails: bedtime, 30-min lead on the rounded time, apple, lapsed each gate to silence, never a shifted time; vacation-open pinned | `SuggestionEngineTests` |
| Reschedule weighting: formula + 1.75× cap in peak shaping only; nil = 1; qualification counts unchanged by weights | `SuggestionEngineTests` |
| Dismissal ledger: trigger-keyed isolation, rounded-displayed comparison (10:05 → 10:20 no re-arm; ≥ 60 displayed re-arms), preallocated-id survival across first save, round-trip, version gate | `SuggestionLedgerTests` |
| Session lifecycle: one presentation per trigger; frozen candidate; no regeneration on field toggles; manual time removes; reopening re-evaluates | `TaskEditorViewModelTests` additions |
| Re-time: series gates (8 / 5 / 3 in-peak), mismatch threshold, series-forward save, one-off exclusion, no title inference | `SuggestionEngineTests` + `TaskEditorViewModelTests` |
| Outcomes: all five + no-outcome cancel from simulated flows; dismissed-then-matched → matched; ± 30 circular window | `TaskEditorViewModelTests` additions |
| Determinism: same distributions + task + constants → same proposal; no clock/zone reads | `SuggestionEngineTests` |
| Engine extension: series scope timed-only filter, entry provenance, day-cap-after-filter order, existing list/global behavior unchanged | `ObservationEngineTests` additions |
| Tuning: 14 keys resolve + clamp + apply; count guard 74 | `RemoteTuningTests` updates |

## 10. As-built deltas (implementation notes, July 25 2026)

The implementation matches this guide with four refinements worth knowing:

- **Windows are HALF-OPEN** `[center - 90, center + 90)` in circular minutes, not
  inclusive ± 90. With inclusive membership, a runner-up window centered exactly 3h
  away shares its boundary minute with the primary - a perfectly unimodal cluster
  sitting on a half-hour boundary would fail its own margin gate. Half-open windows
  make 3h-separated windows genuinely disjoint (the spec's "non-overlapping",
  honored literally); a boundary completion counts in exactly one window. Corollary:
  the 3h runner-up separation stays hardcoded - it is what makes the shipped ± 90
  width disjoint - while `suggest_peak_window_min` remains tunable.
- **`mismatch` is a reported blocked reason.** The spec's coarse-reason list omits
  re-time's sub-3h case; collapsing it into `evidence` would make the denominator
  lie. `suggestion_evaluated` reports `mismatch` as its own value.
- **Preconditions-not-held is an EMPTY evaluation** (proposal nil, blocked nil),
  distinct from every blocked reason - the editor only emits the denominator event
  when a trigger's preconditions actually held, exactly per spec.
- **Session `today`/`nowMinute` freeze at context assembly** (once per editor open,
  re-scoped only on a list change). A chip evaluated minutes into a session uses the
  open-time clock for the lead-time guard - consistent with the frozen-proposal
  lifecycle, and the guard's 30-minute margin absorbs it.

Structural findings (no code needed, pinned by tests/comments): Apple-sourced rows
never open the task editor (`ListDetailViewModel`: "Reminder rows have no editor"),
so edge case 10 is satisfied by construction with a defensive engine guard kept;
no suggestion path consults vacation state, so edge case 12 ("chips work normally")
is the default.

## 11. External setup checklist produced by this feature

1. **Firebase console → Remote Config:** create + publish the 14 `suggest_*` parameters
   (values = defaults above). Joins the pending 24 `obs_*` + 6 `letter_*` + 6 `callback_*`.
2. **firestore.rules:** no change (no new synced fields; `allocateTaskId` writes nothing).
3. Everything else is client-side.
