# Mochi — Requirements

*Working title. A companion-driven reminders & todo app.*
*Status: living draft · v0.8 · implementation current through the discovery batch (see Implementation status)*

**Companion docs.** This is the master spec; four docs stand alongside it rather than
inside it, because each is a working surface with its own rhythm:

| Doc | What it is |
|---|---|
| `Mochi-journal.md` | Long-form reference for the Journal tab: screen anatomy, the moment dictionary, the observation card, copy rules |
| `manual-test-plan.md` | The human QA pass, screen by screen |
| `submission-checklist.md` | TestFlight and App Review gating work |
| `waiting-on-assets.md` | Art and design deliverables the build is waiting on |

Superseded working docs (the per-feature implementation guides, the calendar decision
record, the design-comp prompts) are archived under `ProjectDocs/`; everything durable
in them was folded into this doc in v0.8. Code architecture lives separately again in
`MochiBuddy/DesignDocs/`.

---

## Changelog

**v0.8 — July 30 2026** *(current)* · Personal Layer complete · the discovery batch · doc consolidation

- **Personal Layer Feature 6 (Journal tab) shipped**, closing the build order
  1 → 4 → 3 → 2 → 5 → 6. All six features are now in code. The long-form Journal
  reference (screen anatomy, moment dictionary, copy rules) lives in its own
  companion doc, `Mochi-journal.md`.
  → *The Personal Layer → Feature 6.*
- **New top-level section: *The discovery batch*** — the four items taken up after
  the Personal Layer, plus the one that was tabled. Three shipped
  (Best Hours & Day by day · Suggestion reach · Effort size), one is design-locked
  and unbuilt (Editor layout), one is tabled with a full decision record
  (Calendar access). → *The discovery batch.*
- **Doc consolidation.** The seven implementation guides, the calendar decision
  record, and the design-comp prompts were folded into this doc and archived under
  `ProjectDocs/`. Root now carries five living docs: this one, `Mochi-journal.md`,
  `manual-test-plan.md`, `submission-checklist.md`, `waiting-on-assets.md`.
  → *ProjectDocs/README.md* for the archive index.
- **Remote Config pin moved 74 → 84.** Ten new keys from the discovery batch
  (2 `suggest_weekday_*`, 4 `bh_*`, 4 `effort_weight_*`). Console publish is still
  user-owned. → *Implementation status → Remote Config parameters.*
- **Onboarding: a waking-Mochi adoption beat is being explored** for new accounts.
  Splash stays; a first-run-only sequence taps Mochi from asleep to groggy to awake
  to adopted, and the naming beat becomes the adoption moment rather than a form
  field. → *Onboarding → Exploring: the waking-Mochi adoption beat.*

**v0.7 — July 21 2026** — the Personal Layer (new section) · doc renamed
- **Doc renamed** `mochi-design-doc.md` → `mochi-requirements.md`; title updated to match.
  Same living-draft format, no structural changes to existing sections.
- **New top-level section: *The Personal Layer*** — six features with one shared job:
  convert data the app already collects into evidence that Mochi knows the user. Rationale:
  in this category the purchase decision is emotional, not analytical; the layer moves the
  app from tool to companion. Governing rule pinned in the section: **charts measure,
  companions notice** — anything that reads as measurement gets rewritten or cut.
  → *The Personal Layer.*
- **Feature 1 — Name your Mochi + adoption date — RESOLVED** *(revised same-day after
  review)*. Full spec: onboarding naming beat (skippable, default "Mochi"), rename in
  "You" **available in every state incl. lapsed**, `mochiName` + date-only `adoptedOn`
  (stamped at the naming beat, distinct from `createdAt`, timezone-proof, write-once
  **enforced by Firestore security rules**), one-time persisted migration for legacy
  profiles, one templating helper + a brand-vs-pet audit of hard-coded "Mochi",
  precise Unicode sanitization (never strip ZWJ; overlong caps, malformed falls back),
  **promise copy may never embed the pet name** (renames never touch a promise by
  construction), a centralized **`PetIdentityDidChange`** pipeline (action-label
  re-registration → re-lay → widget mirror → live UI), compact-surface truncation
  fallbacks, neutral deletion copy, 23-row edge-case matrix, instrumentation (never
  log the name; no-op renames don't fire events), required test-coverage list.
  → *The Personal Layer → Feature 1.*
- **Feature 4 — Mochi's observations (insight engine) — RESOLVED** *(revised after
  review — statistical-integrity pass)*. Pure `ObservationEngine`; five observation
  types (productive weekday, time-of-day band, momentum, **list return**, comeback),
  each with evidence floors, **evidence-spread gates** (distinct weeks/dates +
  per-day caps — one bulk-cleanup burst can't mint a trait), and margin gates —
  **when unsure, say nothing**. Locked in revision: **completion-local time captured
  at the source** (`completedLocalDate`/`Minute`/`TimeZone`; travel never rewrites
  apparent behavior; widget drain stamps at completion time), canonical
  **minute-level distribution** with bands/histograms as derived views + circular
  time math for Feature 5, **deterministic hysteresis** (stability replayed as a pure
  function over synced data — cross-device agreement by construction; switch *and*
  retire transitions; per-type policies), momentum vacation/lapse normalization via a
  new synced **interval log** (honest fallback: silent where history is unknowable),
  **list attention removed** (pre-action neglect observations deliberately rejected)
  in favor of the after-action list-return event, comeback evidence strengthened
  (8 events, date + task/series diversity, median **and** p75 gates),
  provenance-carrying `DistributionResult` (no silent global fallback),
  `ObservationCandidate`/`QualifiedObservation` type split, `observation_evaluated`
  denominator event (≤1/type/day, no payloads ever), per-UID ledger namespacing +
  algorithm versioning. `CompletedTaskStat` extended (task/series ids, local context,
  `hasTime`, `isRecurring`, `source`, optional `rescheduleCount` — nil ≠ 0); 24
  `obs_*` Remote Config keys; DEBUG observation inspector with replay timeline;
  25-row edge-case matrix + required test list. → *The Personal Layer → Feature 4.*
- **Feature 3 — Weekly letter from Mochi — RESOLVED** *(revised after review)*. A
  letter is an **immutable artifact of a closed letter period** — Monday 00:00 to
  the effective Sunday send time (the cutoff *is* the send instant, resolving the
  Sunday-19:00 vs. closed-week contradiction; completions after it belong to the
  next period), identified by period-start date (`letter-2026-07-20`, no ISO
  week-year trap) under the **synced profile timezone** as the one authoritative
  zone. Composed exactly once behind an **online composition barrier** (flush
  pending writes, server-backed inputs, transaction with existence precondition —
  determinism over stale inputs would deterministically compose the wrong letter);
  loser discards, provenance stored (composer/copy-deck versions, period bounds,
  summary hash). Period classification (great / steady / quiet / rough /
  vacation-partial) drives **template-level** constraints: rough letters use a
  restricted set with no quantified facts, task titles, observations, or asks (the
  numeral scan is a backstop, not the policy). Two-phase beat selection —
  **structural beats** (presence / vacation / quiet) inserted first, never
  displaced; optional beats by priority; **max one insight-family beat**
  (observation XOR list return). Dormancy gated by a deterministic synced
  engagement marker (`activityWeeks/{periodId}`, create-only; foreground and
  notification taps count, background work doesn't); letter notifications laid
  **only for already-non-dormant periods**; the notification is an invitation,
  never the delivery. **Both share variants rendered at composition** from
  structured beat data (no string surgery on immutable prose) + pet-name snapshot
  (renames never edit postcards). Budget order amended: promises → mood pings →
  rundowns → letter. `LetterArchiveView` owned by the Personal Layer (routed from
  "You" now, Journal later — Feature 6 becomes navigation only).
  Diagnostic-grade open-rate instrumentation (`letter_indicator_shown`, opens by
  source, within-user comparisons, sample floors — a diagnostic, not a verdict).
  6 `letter_*` Remote Config keys; 23-row edge-case matrix + required test list.
  → *The Personal Layer → Feature 3.*
- **Feature 2 — Anniversaries & memory callbacks — RESOLVED** *(revised after
  review)*. Milestones 1 week / 1 month / yearly from `adoptedOn`, pure date-only
  math (calendar-clamped), no stored schedule; delivery = rundown opener +
  `CelebrationCenter` banner, **no new notification class or slots**. A **general
  same-date collision rule** (streak milestone owns the day; anniversary suppressed
  there, remembered in the letter; works whether day-7 and week-1 land together or
  adjacent) and **one canonical rundown priority: streak milestone > anniversary >
  crushed yesterday > callback > observation** — no second source of truth.
  Callbacks (best day, recovery, streak era, date echo) gated by a named
  **`RundownEmotionalRegister`** — predicted *baseline* at fire time incl.
  projected taper, never the device-local buffer-lifted mood (a pet can't unlock
  trophy copy; devices agree) — content+ any type, uneasy/anxious recovery-only,
  floor/chronic none. **Once-until-changed fact identity** (canonical cross-type
  `factId`s) replaces the 30-day cooldown; **fact-age floors** (7d) separate from
  the 21-day relationship floor; best-day distinct identities + tie-aware wording;
  recovery requires a ≥ 24h-overdue contributor and its template family is
  structurally banned from counts/magnitude/"used to" forms (the comparative
  example that broke the ban is replaced); date echo never claims "whole list"
  (data can't prove it); `bestStreakAchievedOn` contract (atomic, strictly-exceeded
  only, never guessed for legacy) + same-run celebration suppression (14d). A
  deterministic **selection contract** (date echo > recovery > best day > streak
  era; never-told first; only the winner consumes cadence; a losing date echo
  expires, never backdates). Vacation: month+ marks acknowledged **past-tense** in
  the first post-re-entry rundown (interval-log-derived; skipped deliberately if
  the rundown toggle is off); 1-week mark dies quietly; lapse: skipped forever,
  never backdated. Device-local cadence honestly documented (per-device once-ever;
  synced history is the v2 hatch). `callback_evaluated` denominator event with
  coarse blocked reasons; 6 `callback_*` Remote Config keys (milestone set not
  tunable); 23-row edge-case matrix + required test list.
  → *The Personal Layer → Feature 2.*
- **Feature 5 — Suggested times — RESOLVED** *(revised after review)*. Editor-only,
  one chip, one tap, never modal, **never auto-set**; absent when unsure — and
  **"bimodal means silence" is now structural**: evidence qualifies on raw
  day-capped counts (weights shape a qualified peak, never manufacture
  qualification), then the peak must clear share (0.35 in ±90 min), **peak-date
  spread** (≥ 3 distinct dates in-window), and a **runner-up margin** (≥ 0.10 over
  the best non-overlapping window ≥ 3h away) — 6-at-9am/6-at-6pm produces silence,
  not a tiebreak. Two triggers: new-time, and **re-time** with consent-accurate
  copy ("Change its time?" — it changes the *due time*: overdue onset, stress,
  occurrences; never "move the reminder") and the plan-vs-deadline inference
  limitation named. Scope = **highest qualifying scope** (series 8/5-dates/3-in-peak,
  else list — guarded so one daily habit can't speak for a list (≥ 3 identities,
  ≤ 40% single-series weight) — else global), reason copy pinned to `scopeUsed`.
  Pinned rounding (nearest half hour, quarter-ties earlier, never across the date
  boundary; guardrails evaluate the rounded time; mismatch measured unrounded) +
  a 30-minute lead-time guard (silence, never moved later). Apple-sourced: no chip
  in v1 (EventKit alarm semantics named, deferred). Dismissal once-until-changed,
  **keyed by trigger + rounded displayed proposal**, task id preallocated at
  editor open; session-frozen chip lifecycle (no flicker). Outcomes **classified
  at save** (cancel = no outcome; dismissed-then-matched = matched; accepted
  primary, matched supporting with its chance component reported separately),
  stratified by trigger/scope/cohort — re-time has no global control, so it gets
  absolute acceptance + a **downstream retention signal** (suggestion survived the
  next occurrence / completed near it / re-time reversed — coarse buckets only).
  Validator claim narrowed: this validates insight **actionability**, not the
  layer's emotional value. 14 `suggest_*` Remote Config keys; 24-row edge-case
  matrix + required test list. → *The Personal Layer → Feature 5.*
- **Feature 6 — Journal tab — RESOLVED** *(revised after review)*. **The Personal
  Layer design is complete.** Deliberately *only* a container: no new engines, no
  new gates, zero Remote Config keys. Fourth tab (**Home · Tasks · Journal ·
  You**), static "Journal" label; "Nori's Journal" header as a **full localized
  format string** (never possessive concatenation); the card reads "Nori has
  noticed" with the live name. **One unified story timeline** (letters by
  reference + moments interleaved; the unread-letter hero is a presentation state
  of a timeline row, never a copy; multi-unread defined; Feature 3's components
  reused as row/detail). Philosophy restated as **record vs. grade**: the footer
  keeps strip/trend/done-this-week/best streak, drops on-time % (a grade), drops
  the ungated busiest-weekday caption (Feature 4's job), and **drops coins**
  (currency state, not a record). Moments: **synced, create-only, natural ids
  that identify events, not categories** (`streak-milestone-{count}-{date}`,
  `vacation-return-{intervalId}`, `list-return-{listId}-{sourceEventId}`) with
  **deterministic payloads derived from immutable event facts** (racing writers
  produce content-identical documents; snapshots travel with the qualifying
  event; original-locale prose kept — postcard rule). **Adoption moment atomic**
  (batched with `adoptedOn`; deterministic synthesis fallback; legacy copy "The
  day your story began" never implies the current name); **backfill = adoption
  only** (the best-streak idea dropped: superlatives go stale, immutable text
  must never become false). Lapse freezing pinned: **`effectiveNow =
  lapseStartedAt`** (no drift, no decay-to-zero; reactivation resumes live over
  full retained history). Timeline dates from **stored** letter zones + date-only
  `occurredOn` (travel moves nothing between months; month pages = two bounded
  queries + pure merge). Rules validate type/schema/fields/id-prefix, not just
  create-only. Viewport-based section impressions; **anti-churn labeled
  correlation, not proof**. 21-row edge-case matrix + required test list.
  → *The Personal Layer → Feature 6.* Build order for implementation stands:
  1 → 4 → 3 → 2 → 5 → 6.
- Data model: `mochiName`, `adoptedAt` added to `users/{uid}`. Onboarding: naming beat
  appended to the *Meet Mochi* step. Widget: `mochiName` added to `MochiWidgetState`.

**v0.6.1 — July 19 2026** — hardening pass, no design changes
- **Promise-integrity fixes.** (1) Weekdays/custom recurring promises no longer fall into a
  repeating time-interval trigger (which re-fires every "now → due" span and traps below
  60s); without calendar components a promise schedules its single next fire and leans on
  the re-lay. (2) An overdue-but-not-yet-rolled recurring occurrence now promises its
  **next** occurrence, so a re-lay during the overdue window can never drop tomorrow's
  reminder for a user who doesn't reopen the app.
- **Complete-from-widget re-enabled on vacation** per the locked state-variant table
  (vacation removes pressure, not function); the table is now pinned by shared
  `DisplayState` rules + a test.
- **Streak-milestone celebrations wired end-to-end** (in-app): every completion surface
  (Home, Tasks, notification actions, the widget drain) posts through one
  `CelebrationCenter`; Home shows the banner. In-app by design — milestones only land with
  the app open or at drain time, so a push would always arrive mid-session.
- **Remote Config applied strictly before anything computes** (the container is built
  after activate+apply), the shh action label reads the tuned duration, the widget-mirror
  horizon tracks `notif_horizon_days`, and `vacation_grace_wake` now **derives from
  `mood_anchor` unless set explicitly** (wake target is defined as = A).
- **Timezone-change re-lay wired** (wall-clock reminder semantics); zero-length bedtime
  windows are sanitized to the default at every persistence boundary.

**v0.6 — July 19 2026**
- **Widgets — RESOLVED.** Full technical spec locked. WidgetKit extension + a shared
  mood-engine framework; **static image assets only** (never load Rive in the extension);
  **all reads from the App Group** (no Firestore/EventKit/network at render time). Surfaces:
  home **small/medium** (large is fast-follow) + lock-screen **circular/rectangular/inline**
  (monochrome). **Complete-from-widget confirmed for v1** — a durable write to the source of
  truth (Firestore / EventKit) — alongside home-screen **tap-to-pet**; both via App Intents
  (iOS 17+). **The widget timeline *is* the notification mood-forecast, reused verbatim**
  (future-dated entries, zero wasted reloads, same invariant). New **App Group data contract**
  (`MochiWidgetState`): the app mirrors theme + next-task projection + flags in. **iOS 26
  rendering:** mark Mochi `fullColor` so mood still reads through Liquid-Glass tinting.
  **Vacation widget = resting pose** (distinct from lapsed's *asleep*, no "Wake Mochi" CTA),
  preserving the locked "don't conflate the two calm states" decision. Asset set = **6 mood +
  asleep + resting**, all required to read as monochrome silhouettes for the lock screen.
  → *Widgets.*

**v0.5 — July 19 2026**
- **Vacation mode — RESOLVED (was backlog / roadmap #4).** Elevated from the feature
  backlog to a first-class section. Re-entry — the last open design problem — is designed:
  **freeze-and-triage** for one-off overdue tasks (set aside into a "came due while you were
  away" bucket, zero stress, due dates untouched), **both** a fixed end date and an
  open-ended "until I turn it off" mode, the latter protected by a 14-day in-app check-in and
  a **30-day hard auto-expiry cap**. The period is **truly silent** — no mood pings,
  reminders, celebrations, or push of any kind, and no per-task "remind me anyway" escape
  hatch in v1. Streaks **freeze rather than break**; the re-entry **grace buffer** reuses the
  comfort-buffer subsystem (wake near content, drift to true mood over 24h); vacation is its
  own instrumentation state, **excluded** from the daily mood-distribution metric. Includes
  full UI specs, four flow examples, use cases, and a 20-row edge-case matrix.
  → *Vacation mode.*
- **Platform scope — DECIDED.** iOS only. Android is not planned; the whole stack
  (Apple/Google auth, lock-screen widgets, Watch, Apple Reminders) leans iOS and we're
  committing rather than hedging. → *Still to flesh out.*
- Roadmap item #4 (Vacation-mode re-entry) moved to ✅ Resolved.

**v0.4 — July 18 2026**
- **Notifications — RESOLVED (was ON HOLD).** Closed every open item. **Copy & voice:**
  three classes, three voices (mood pings = Mochi's blame-free monologue, never a task name;
  reminders + rundown = always name the task; celebrations = celebratory), two-pool floor copy
  (acute → chronic), emoji celebrations-only, task names shown by default with an opt-in
  "hide on lock screen" toggle. **Constants:** floor taper 4→3→2→1/day, taper resets only on
  a genuine recovery, no entry grace (fire on crossing), sparse streak celebrations (7 / 30 /
  then every 50), a no-cost "you crushed yesterday" beat folded into the rundown. **Actions:**
  reminders get Complete + Snooze menu (1h / tonight / tomorrow); mood pings get Pet +
  "shh — 24h"; expressive Mochi faces everywhere but intensity-capped on predicted mood pings.
  **Winback:** lapsed = pure-functional reminders, zero come-back nudge. **Instrumentation:**
  everything logged by mood state, alert-only tripwire, never log task titles.
  → *Notifications.*
- **Mood pings — technical requirements — RESOLVED.** Formalized the consistency invariant
  (one `mood(t)` sampled at two times, agree by construction), the forecast input model
  (simulate deterministic app-closed events: future due crossings, recurrence rolls, vacation
  auto-expiry; cap horizon at entitlement expiry), the core requirements, and a 20-row
  edge-case matrix. → *Notifications → Mood pings: technical requirements.*
- **Dev tool — notification scheduler tab — RESOLVED.** A `#if DEBUG`-only tab in "You" that
  plots the pending queue against the forecast curve, with a slot-budget meter, live engine
  state, re-lay log, and live invariant checks. → *Notifications → Dev tool.*
- Roadmap item #3 (Notifications) moved to ✅ Resolved.

**v0.3 — July 18 2026**
- **Recurring tasks × mood engine — RESOLVED.** Locked the "one live occurrence"
  invariant, re-stamping, calendar-anchored default, and silent missed-logging.
  → *Task management → Recurring tasks.*
- **Entitlement & subscription states — RESOLVED.** New section: `trialing / active /
  billing_grace / lapsed`. "Finish what you started" lapsed state, Mochi asleep (not
  sad), data never deleted, `billing_grace` treated as fully entitled.
  → *Entitlement & subscription states.*
- **Multi-device guardrails — RESOLVED (minimal).** Atomic coin writes; device-local
  comfort buffer. → *Tech → Multi-device.*
- **Notifications — PARTIALLY RESOLVED, section ON HOLD.** Locked: local/on-device
  architecture (no server), two-class model, escalate-at-the-floor cadence with
  anti-burnout brakes, no per-completion push. Open: copy library, exact constants,
  actions/richness. → *Notifications.*
- Added **Remaining agenda / roadmap** to track open discussion items.

**v0.2** — prior living draft (mood algorithm spec, economy, legal, onboarding, tech).

---

## Implementation status

> 🛠 **As of July 30 2026 (v0.8).** Everything the changelog resolved through v0.6.1,
> the complete Personal Layer (Features 1 → 4 → 3 → 2 → 5 → 6, the pinned build order
> run to the end), and three of the four discovery-batch items are built and covered by
> the automated suite. **`firestore.rules` is fully deployed** (adoptedOn write-once,
> letters, and activityWeeks July 24 2026; Feature 6's moments block confirmed live
> July 27 by diffing the console against the repo, byte-for-byte identical). Features 2
> and 5 needed no rules change, and neither does the discovery batch. The one piece of
> user-owned work the code is still waiting on is the Remote Config publish; everything
> else outstanding is App Store Connect and RevenueCat account work, tracked in
> *Outstanding external setup* below.
>
> **Not built:** the editor-layout ghost pill (design locked, spec in *The discovery
> batch → Editor layout*). **Tabled:** calendar access (*The discovery batch → Calendar
> access*). Next up is the TestFlight push tracked in `submission-checklist.md`.

| Spec section | Status | Where it lives (code) |
|---|---|---|
| Mood algorithm | ✅ Shipped pre-v0.3 | `Mood/MoodEngine.swift` |
| Recurring tasks × mood engine (v0.3) | ✅ Implemented + tested | `Tasks/RecurrenceRoller.swift`; roll-forward re-stamps `dueAt`, silent miss log = `missedCount`/`lastMissedAt` on the task doc |
| Entitlement & subscription states (v0.3) | ✅ Implemented + tested | `Membership/MembershipSession.swift` (`billingGrace` case incl.), lapsed quiet-checklist degradation across Home/Tasks/You, "Not now" pass-through on the lapsed gate, `-mochiStartLapsed` dev arg |
| Multi-device guardrails (v0.3) | ✅ Verified | Coin writes were already `FieldValue.increment`; comfort buffer is device-local UserDefaults |
| Mood pings: technical requirements (v0.4) | ✅ Implemented + tested | `Mood/MoodForecast.swift` (one engine parameterized by time; simulates due-crossings, recurrence rolls, vacation auto-expiry incl. the 30-day cap; horizon capped at entitlement expiry). The consistency invariant is an automated test: every planned ping's baked band == `mood(fireTime)` recomputed |
| Notification scheduling (v0.4) | ✅ Implemented + tested | `Notifications/NotificationPlanner.swift` (cadence table, floor taper 4/3/2/1, quiet-hours drop-not-shift, suppression composition, 64-slot budget promises-first + backstop), `NotificationPlanDiff` (scoped re-lay, promises never nuked), `NotificationOrchestrator` (debounced re-lay on the full trigger list), `UNNotificationScheduler` (thin adapter) |
| Copy & voice, actions, richness (v0.4) | ✅ Implemented + tested | `NotificationCopy` (three voices, acute/chronic floor pools, rotation deck, emoji celebrations-only), `TaperTracker` (genuine-recovery reset, blips never reset), reminder Complete + snooze menu, mood-ping Pet + shh-24h (`NotificationActionHandler`), interruption levels + thread coalescing, task-name privacy toggle |
| Cadence & celebration constants (v0.4) | ✅ Implemented + tested | Streak milestones 7 / 30 / then every 50 (`StreakMilestones`), "crushed yesterday" folded into the rundown title (threshold 5), morning-rundown ranking (`RundownRanker`) evaluated at fire time |
| Winback & instrumentation (v0.4) | ✅ / partial | Lapsed = promises only, indefinitely, zero comeback copy (planner-tested). Telemetry is a protocol with an os_log impl, mood-state tagged, titles never logged; Firebase Analytics backend waits on roadmap #7 |
| Dev tool: scheduler inspector (v0.4) | ✅ Implemented, sim-verified | `You/DevScheduler/` behind `#if DEBUG`: forecast curve + pending queue chart, quiet-hour shading, slot meter, taper/shh state, live invariant check, time travel, force re-lay. Found a real bug on first open (stale rundowns for a lapsed user; fixed via `MembershipSession.onChange` re-lay) |
| Vacation mode (v0.5) | ✅ Implemented + tested, sim-verified | `VacationSchedule.effectiveEnd` (open-ended auto-expires at the 30-day cap; `vacationStartedAt` persisted), `You/Vacation/VacationReentryService.swift` (bucket of one-off tasks overdue at the effective end, grace buffer lift to the content anchor over 24h, streak freeze via lastActive bump, 14-day open-ended check-in), Home banner + End now + resting pose pinned + triage sheet (per-row and bulk complete / spread-reschedule / dismiss / Later). Planner also mutes mood pings through the 24h post-vacation grace window |
| Widgets (v0.6) | ✅ Implemented + tested | `MochiWidgetExtension` target + `MochiShared/` sources compiled by both targets (in place of a framework); `MochiWidgetState` contract in the App Group (`MochiShared/WidgetState.swift`), mirrored by the app after every re-lay (`WidgetStateMirror`); timeline = stored baseline curve + live shared comfort buffer; small/medium + all three lock families; Pet + Complete intents; state variants active/lapsed/vacation |
| Remote Config | ✅ Wired + published | `Tuning/RemoteTuning.swift`: `TuningSource` protocol over Firebase, pure `ResolvedTuning.resolve` with range clamping (a console typo degrades to the shipped default, never a broken invariant). Applied **before `AppContainer` is built** (the app awaits activate+apply, then constructs the container), so nothing ever computes on pre-apply values and mood(t) is strictly deterministic per session; the background fetch lands next launch. Skipped entirely under tests. All 24 parameters are published in the console and pinned by tests (`consoleKeysMatch`, `everyKeyDecodes`); hours/days→seconds conversions live in pure `ResolvedTuning` derived properties with their own non-default tests |
| Celebrations (in-app) | ✅ Implemented + tested (v0.6.1) | `Rewards/CelebrationCenter.swift` + `TaskCompletionStore.onMilestone`: every completion surface (Home, Tasks tab, notification Complete action, widget drain) posts a landed sparse milestone (7 / 30 / then every 50) through the one center; Home shows the banner (`celebrationText`, dismissible, fires only on the completion that reaches the milestone). No push celebration class exists **by design** — see deltas |
| Personal Layer · Feature 1: Name your Mochi + adoption date (v0.7) | ✅ Implemented + tested | `PetIdentity/`: `PetNameSanitizer` (Unicode-precise: controls/bidi stripped, banned whitespace becomes a separator, ZWJ/variation selectors never touched, 16-grapheme cap on boundaries) + pure `PetNameFieldPolicy` behind a UIKit-backed `PetNameTextField` (marked text never blocked, cap on commit) · `AdoptedOnDate` (date-only YYYY-MM-DD, strict round-trip validation, zone-free display) · `PetIdentityStore` (@Observable; one-time persisted migration backfills `mochiName`/`adoptedOn` from `createdAt` with a per-UID flag, doubles as the interrupted-onboarding backstop at `enteredHome`; `PetIdentityDidChange` pipeline: sanitize+persist → action-label re-registration (`NotificationActionTitles`, verb+~12-char compact budget, width-estimated) → `petIdentityChange` re-lay (mood pings + rundowns rewritten; **promises pet-name-free by construction** — the old "Mochi is rooting for you" promise body was removed as a spec violation) → widget mirror (`mochiName` optional in `MochiWidgetState`, stale snapshots decode and fall back) → live UI). Naming beat closes Meet Mochi (skippable, both buttons stamp write-once `adoptedOn`, name used on the very next screen); "Your Mochi" group + rename sheet in "You" (available in every state incl. lapsed); brand-vs-pet audit swept every surface (mood/rundown pools are `{name}` templates through the one `PetCopyTemplate` helper, they/them pronouns; Home/Tasks/editor/You sub-screens/onboarding-post-beat/returning flow/widget incl. VoiceOver); deletion screen lists name + adoption date factually. `firestore.rules` enforces `adoptedOn` write-once server-side (deployed July 24 2026). Instrumentation: `pet_named` (custom bool) / `pet_renamed` (count), never the string |

| Personal Layer · Feature 4: Mochi's observations (v0.7) | ✅ Implemented + tested (no production surface yet, by build order) | `Observations/`: pure `ObservationEngine` (all five v1 types with their evidence floors, spread gates incl. the per-day cap, and margin gates; weekday from one-off completions only; bands + histograms as derived views over canonical minutes; momentum eligibility from the synced interval log with the honest pre-log silence rule; list return as an after-action event; comeback with median + p75 gates; 14-day deterministic-replay hysteresis with switch AND retire; explicit calendar/now parameters, zero clock reads, determinism + current-zone-independence pinned by tests) · `ObservationCandidate`/`QualifiedObservation` type split enforced at compile time · `DistributionResult` with explicit `scopeUsed` provenance + circular minute math (Feature 5's contract, ready) · per-UID `ObservationLedger` (surfacing cadence ONLY: rundown weekly cap, same-week letter/rundown dedup, momentum cooldown, list-return once-per-event, copy rotation, algorithm/schema version gate, cleared on account deletion) · `ObservationCopy` pools (qualitative by locked rule, `{name}` templated, night band affirming) · `observation_evaluated` (≤1/type/day) + `observation_shown` os_log telemetry, never a conclusion payload · `ObservationService` orchestrator (fetch horizon = replay 90 + window 42 days). Inputs: `CompletedTaskStat` extended with task/series ids + completion-local date/minute/zone stamped at the source (Firestore write, widget queue stamps at TAP time; legacy rows re-interpret under the current zone, honestly marked derived); recurring spawns inherit `seriesId`; `users/{uid}.observationIntervals` + `observationLogSince` synced, maintained by `ObservationIntervalRecorder` (vacation entry, TRUE vacation end via re-entry, lapse via the membership hook, reconcile backstop at home entry). DEBUG observation inspector in the DevScheduler tab (gate-by-gate evidence, replay glyph timeline, ledger state, shared time travel). Consumers arrive with Features 3/2/6; 24 `obs_*` Remote Config keys wired + test-pinned (published July 25 2026) |

| Personal Layer · Feature 3: Weekly letter from Mochi (v0.7) | ✅ Implemented + tested, live compose confirmed against the deployed rules | `Letters/`: `LetterSchedule`/`LetterPeriod` (Monday start, send-hour cutoff with the bedtime clamp moving the cutoff, plain-date ids, attribution window owning the post-cutoff tail, authoritative-zone parameterization; first consumer of the synced `profile.timezone`) · pure `LetterComposer` over `PeriodSummary` (classification table with precedence incl. vacation-partial > rough; two-phase beat selection with structural beats first; insight-family XOR cap; rough letters draw ONLY from the structurally restricted pools, asserted by test, numeral scan as backstop; both share variants composed from beat data, never string surgery; FNV-1a hash rotation with don't-repeat-last-N vs the synced archive, no stored rotation state) · `FirestoreLetterRepository` (archive reads cache-friendly; first composition = the app's ONE fire-and-forget exception: `waitForPendingWrites`, server-backed reads, `runTransaction` create with existence precondition, first writer wins, loser displays the winner) · `LetterCompositionService` on user-visible foreground only (stamps the create-only `activityWeeks/{periodId}` marker - notification taps count via foregrounding, background work structurally can't; gates: first-full-period after `adoptedOn`, dormant skip, full-vacation skip, lapse skip, active-vacation defers late-never-wrong; no backfill) · letter notification class (id = letter doc id, budget order promises → mood → rundowns → LETTER, laid only for a non-dormant period via `letterInputProvider`, vacation/lapse/toggle suppressed, `.active`, invitation-only copy; tap deep-links Home → detail) · `weeklyLetter` pref + toggle row · UI: temporary "Mochi's letters" You row → `LetterArchiveView`/`LetterDetailView` (readAt on open, synced), Home quiet-envelope indicator, `ImageRenderer` share card (private default, full per-share opt-in, rough never offers full; placeholder wordmark) · diagnostic telemetry (composed/indicator_shown/opened-with-source/shared, no text ever) · `letters` + `activityWeeks` rules blocks (create-only + readAt-only update; deployed July 24 2026, composition confirmed live) · AccountEraser covers both subcollections · DEBUG force-compose in the DevScheduler. Known gaps: ~~anniversary references in the milestone beat wait for Feature 2~~ (closed July 24 2026 - Feature 2 wired the anniversary/collision beats); rules immutability untested client-side (no emulator harness); Home envelope/detail/share card still to be driven end-to-end in the sim |

| Personal Layer · Feature 2: Anniversaries & memory callbacks (v0.7) | ✅ Implemented + tested, inspector sim-verified July 24 2026 (live: next-milestone date math, relationship-age gate flipping exactly at day 21 under time travel, REAL recovery + best-day facts mined from the profile's own history with correct factIds and 7-day fact ages, register tracking the predicted baseline into `closed` on floor mornings, clean ledger, 4 pending rundowns correctly carrying no Personal-Layer line; banner day itself not yet drivable live - next natural milestone Aug 8) | `Memories/`: pure `AnniversaryCalendar` (1 week / 1 month / yearly from write-once `adoptedOn`, platform clamps Jan 31 → Feb 28/29 and Feb 29 → Feb 28, deliberately not remote-tunable; stateless vacation deferral derived from the interval log: month+ marks acknowledge past-tense on the ONE first post-re-entry rundown, week marks skipped) · pure `CallbackFactMiner` over the SAME 132-day fetch Feature 4 makes (no new query): best day (count + distinct-identity floors, latest-wins tie rule + tie-aware copy flag), recovery (≥3 distinct overdue clears in 48h with ≥1 ≥24h late; greedy non-overlapping episodes; lateness computed in each record's own completion zone), streak era (best ≥7, active-run celebration quiet window derived from `lastActiveDate`, era phrasing only with `bestStreakAchievedOn`, legacy never guessed), date echo (clamped month-back day clearing the best-day floor, date-bound, fact-age exempt); canonical cross-type `factId`s (`completion-day-*` shared by best day + echo, FNV-1a recovery hash, `streak-record-count-date`); relationship activation ≥21 days; fact-age floors · `RundownEmotionalRegister` (bands `MoodForecast.baseline(at: fireAt)`, NEVER displayed - buffer lift changes nothing by construction, pinned by test; chronic taper stretch closes an uneasy morning; open / recoveryOnly / closed → type admission) · `PersonalLayerPlanner` = THE canonical priority (streak milestone > anniversary > crushed yesterday > callback > observation, one line per rundown ever; a streak-claimed date renders NOTHING - celebrations stay in-app per v0.6.1 - and suppresses the anniversary on rundown + banner while the letter still remembers both; deterministic selection contract: echo > recovery > best day > era, never-told > told-and-changed, recency, stable-id ties; only the winner consumes; a losing date echo expires silently) with cadence threaded across the whole laid horizon (weekly cap 2, min gap 3) · per-UID `CallbackLedger` (sibling of ObservationLedger, own schema gate + namespace: fold = freeze past assignments into the never-pruned told-once record, replace future wholesale so re-lays are idempotent and a dropped future line un-consumes; stores rendered openers as `{name}` templates so renames re-render without burning rotation; banner once-per-milestone; `callback_evaluated` throttle; cleared on account deletion beside the observation ledger) · `MemoriesService` orchestrator (assign + commit per re-lay via `orchestrator.personalLayerProvider`, letterInputProvider pattern; the rundown dress case takes a `PersonalLayerSlot` where planner-decided-none ≠ no-planner-fallback; crushed-yesterday now priority-governed, observation tier is Feature 4's first live rundown consumer through `ObservationService.surfaced`; anniversary banner on day's first open via a second `CelebrationCenter` slot consumed streak-first by Home, silent on vacation/lapse) · `MemoriesCopy` pools ({name} templates, coarse relative time, counts in best-day/echo only, recovery family structurally restricted + asserted by test: {name} the only slot, no digits, no asks, no banned constructions; echo never claims "whole list") · letters: `PeriodSummary.anniversary` fact (built by `PeriodSummaryBuilder.anniversary` over the attribution window + vacation intervals), milestone beat now three-way (streak-only / anniversary-only incl. honest vacation-passed phrasing / collision pool carrying BOTH: "Seven days of streak, one week of us"), anniversary in `summaryHash`, `LetterCopy.version` → 2 (closes Feature 3's noted gap) · `bestStreakAchievedOn` end-to-end (model/DTO validated decode/`RewardsStore` strict-exceed stamp atomic in the one `saveStreak` merge/caching mirror/vacation re-entry pass-through, never stamped there) · telemetry `anniversary_shown` (tier+surface) / `callback_shown` / `callback_evaluated` (denominator: qualified + coarse blocked reason, ≤1/type/day), no payloads ever · DEBUG memories inspector in DevScheduler (milestone today/next, register at the time-travel cursor, per-type mining verdicts, ledger dump) · 6 `callback_*` Remote Config keys wired + test-pinned (published July 25 2026); `firestore.rules` needs NO change (owner update rule already admits the new field; strict-exceed monotonicity is client-side by spec). Long-form build notes: `ProjectDocs/build-notes/feature2-implementation-guide.md` |

| Personal Layer · Feature 5: Suggested times (v0.7) | ✅ Implemented + tested (app boots clean with the feature live; interactive chip drive in the sim pending - Mac was locked during the build session) | `Suggestions/`: pure `SuggestionEngine` (qualification on RAW day-capped counts: evidence + distinct-date floors per scope, deterministic 48-center window scan with HALF-OPEN ±90 windows so 3h-separated windows are genuinely disjoint - a boundary completion counts once; peak share ≥ 0.35, peak-date spread ≥ 3 inside the primary window, runner-up margin ≥ 0.10 vs the best window ≥ 3 circular hours away, so bimodal means silence by construction; highest-QUALIFYING-scope precedence series > list > global with the list concentration guard (≥ 3 identities, no identity > 40% of the capped count); reschedule weight `1 + min(count,3) × 0.25` shapes the peak of an already-qualified distribution only, nil = unknown = 1; friendly rounding pinned (nearest half hour, quarter ties earlier, next-day 00:00 falls to 23:30); guardrails silence, never clamp: bedtime on the ROUNDED minute, 30-min lead for today-due, lapsed, defensive Apple guard; re-time = series-gated (8 timed / 5 dates / 3 in-peak) + unrounded-peak mismatch ≥ 3h, one-offs structurally excluded, no title inference; dismissal re-arm at ≥ 60 DISPLAYED circular minutes; pure end to end, zero clock reads) · engine contract extended in place: `DistributionResult.Scope.series` + per-entry provenance (`minute/day/identity/rescheduleCount`), `ObservationEngine.suggestionDistribution(scope:)` with day-cap-after-filter and the timed-only series rule · `SuggestionProposal` tier-typed so reason copy CANNOT overreach (`SuggestionCopy` takes the tier: series/list/global voices, list-name-gone narrows to global phrasing, re-time consent copy says DUE TIME and persists-forward, "reminder" banned by test) · per-UID `SuggestionLedger` (trigger-keyed `{trigger}|{taskId|seriesId}` dismissals storing the displayed minute, acceptance records capped at 20 for retention, schema gate, cleared on account deletion) · `SuggestionService` (@MainActor session per editor open over the existing observation fetch - no new query; pure re-scope on list change; telemetry; lazy coarse retention buckets when an accepted task/series is next edited) · `TaskEditorViewModel` session lifecycle (one presentation per trigger per session, frozen proposal never regenerates on field toggles, manual changes satisfy or remove, blocked triggers keep re-evaluating while unpresented; save-based outcomes accepted/adjusted/matched(±30 circular)/dismissed/ignored with tapped > matched > dismissed > ignored precedence, dismissed-then-matched = matched, cancel = no outcome) · chip UI in `TaskEditorView.whenBlock` (clock glyph + label + one-line reason + dismiss, whole-row accept button, quiet confirmed state, Dynamic-Type-wrapping reason, no placeholder when absent) · task-id preallocation (`TaskRepository.allocateTaskId` mints without writing; `addTask(id:)` saves through it so a pre-save dismissal survives) · telemetry `suggestion_evaluated` (once per trigger per session where preconditions held, coarse blocked reason incl. the as-built `mismatch` value) / `suggestion_shown` / `suggestion_outcome` (matched always its own component) / `suggestion_retention`, no payloads ever · DEBUG suggestions inspector in DevScheduler (pick any snapshot task, both triggers gate-by-gate at the time-travel cursor, ledger dump) · 14 `suggest_*` Remote Config keys wired + test-pinned, published July 25 2026 (count guard now 84 after the discovery batch) · Apple-source edge case 10 is structural (Reminders rows never open the editor) and vacation edge 12 is structural (no vacation consult anywhere). `firestore.rules`: no change. Long-form build notes: `ProjectDocs/build-notes/feature5-implementation-guide.md` |

| Personal Layer · Feature 6: Journal tab (v0.7) | ✅ Implemented + tested, rules deployed | `Moments/` + `Journal/`: durable `Moment` records on natural event ids (ids identify *events*, not categories, so repeat 30-day streaks and same-date vacation returns never collide) with deterministic snapshot payloads derived from immutable event facts, never live lookups at write time · `MomentWriter` lapse-gated · one unified story timeline merging moments and letters (the hero is a presentation state, not a copy) · record-vs-grade philosophy held: no coins in the footer, no "busiest weekday", nothing that reads as a score · fourth tab (Home · Tasks · Journal · You) with the You tab shedding Stats back to pure settings · zero new engines, zero new gates, zero Remote Config keys. **As-built deltas:** the lapse guard in `TaskCompletionStore` makes the best-streak freeze structural (lapsed completions earn nothing, so the streak can never advance and `onMilestone` can never fire) and the footer needs no special pinning; anniversary moment producers are **two**, not three (day-of detection in `MemoriesService.checkAnniversaryBanner`, written BEFORE dedup so the day counts even when the banner loses, plus vacation re-entry via `MomentWriter.vacationEnded`) and an anniversary that passes while the app is never opened dies quietly, with no backfill inventing it later; list-return moments write from `MemoriesService.assignPersonalLayer` (the layer's most reliable lapse-gated beat) keyed once-per-event by the event itself, not the ledger; vacation-return identity is the interval start's epoch seconds, and a legacy vacation with no `vacationStartedAt` writes no moment; `stampAdoptedOn` became `stampAdoption(_:moment:userId:)` (one `WriteBatch`) so the adoption moment is atomic with `adoptedOn`, with deterministic synthesis as fallback; the letter archive screen is **deleted, not orphaned** (`LetterArchiveView`/`ViewModel`/`Behavior`, `HomeRouter.letterDetail`, `HomeBehavior.PresentedLetter`, `LetterCompositionService.pendingNotificationOpen` all retired) with `TabCoordinator.pendingLetterRoute` as the one notification/envelope handoff; observation cards surface via `surfaced(.journal)` once per (conclusion, day) per VM session, while lapsed loads render through a non-mutating `ObservationLedger.peekLine` so a frozen read-only surface never rotates the deck or logs `observation_shown` (card caps at 3 lines); `journal_opened` logs from `TabCoordinator` on the selection edge, not the view, so pop-backs can't inflate it; timeline pagination fetches both collections fully and merges purely in v1 (bounded by account age, ~52 letters/yr) with the composer taking plain arrays so month-bounded paging slots in later; the 4-week trend renders once the capped stats span ≥ 2 distinct civil weeks and the best-streak tile joins the footer whenever the record is > 0; synthesis repair runs inline in `JournalViewModel.load` (awaited, testable) rather than fire-and-forget. Long-form reference: `Mochi-journal.md` |

| Discovery batch · Best Hours + Day by day (v0.8) | ✅ Implemented + tested, comp-approved | `You/Stats/`: two cards replacing the retired "Your rhythm" four-band card. Pure derivation over `[CompletedTaskStat]` (24 hourly buckets on a 5a-to-5a axis, best-3-hour-window scan, in-window share, per-weekday quartiles with circular handling, per-row qualification), two SwiftUI cards, a state-aware caption generator, the Day by day day picker, and `BestHoursHelpView`. Four `bh_*` keys wired + test-pinned (**console publish pending**). No model change, no migration, no rules change. Spec: *The discovery batch → Best Hours & Day by day* |

| Discovery batch · Suggestion reach: weekday fallback · row badge · push counting (v0.8) | ✅ Implemented + tested | Three independent changes to the shipped Feature 5 machinery, in three commits (push counting first, per its own C4 urgency). **(C)** `rescheduleCount` now increments on an editor move of an incomplete task's due date to a LATER date, and is parsed in `taskItem(id:data:)` so live tasks can read it. **(A)** A weekday-filtered scope tried only as a fallback after the pooled answer is silenced by the runner-up gate, at list and global scope only, with its own lower floors and its own tier-typed copy voice. **(B)** A `clock.arrow.circlepath` badge on Tasks and ListDetail rows (never Home, never Reminders rows) signposting an available re-time, evaluated once per fetch. Two `suggest_weekday_*` keys wired + test-pinned (**console publish pending**). Spec: *The discovery batch → Suggestion reach* |

| Discovery batch · Effort size (v0.8) | ✅ Implemented + tested, comp-approved | An optional four-level effort rating (Tiny · Small · Medium · Large) stored as nominal `estimatedMinutes: Int?`, weighting `MoodEngine` momentum so one large task lifts Mochi about as much as three small ones. Coins stay flat by design. The largest ripple was structural: `completionTimes` became weighted entries rather than bare dates across the snapshot, orchestrator, planner, memories service, and every direct baseline caller, with the weight carried as a **sidecar** so the two count-based consumers (`crushedYesterday` and the notification threshold) keep working on `.count` unchanged. Editor pill on the Priority row under its own EFFORT eyebrow (no eighth block), one Stats tile, recurring inheritance, four `effort_weight_*` keys wired + test-pinned (**console publish pending**). Widget needed no work: the drain re-reads the full document. Spec: *The discovery batch → Effort size* |

| Discovery batch · Editor layout (ghost pill) | ⬜ **Design locked, NOT built** | The one remaining question from the batch: how the editor presents a new-time suggestion. Locked as a ghost inside the time pill rather than a card below it, with one tap accepting and opening the wheel seeded at the suggested minute, and nothing committed until the user taps. All view-and-VM work; no engine, model, or persistence change. No design comp exists. Spec: *The discovery batch → Editor layout* |

### Remote Config parameters (84 keys · 74 published, confirmed remote-sourced July 25 2026 · 10 discovery-batch keys pending)

The console holds exactly these keys, all currently set to the shipped defaults (so
behavior is unchanged until a deliberate tuning pass). The canonical list lives in
`RemoteTuning.numberKeys`/`jsonKeys` and a test fails if either side drifts.

- **Mood engine (Number):** `mood_anchor` 58 · `mood_lateness_cap_hours` 48 ·
  `mood_base_sting` 0.4 · `mood_stress_saturation` 4 · `mood_momentum_max` 42 ·
  `mood_momentum_saturation` 2.5 · `mood_momentum_gate` 20
- **Notifications:** `notif_mood_pings_daily_ceiling` 4 · `notif_floor_taper`
  `[4,3,2,1]` (JSON) · `notif_cadence_very_sad` / `_anxious` / `_uneasy`
  `{"count":N,"spacingHours":H}` (JSON) · `notif_backstop_days` 7 ·
  `notif_horizon_days` 7 · `notif_shh_hours` 24 · `notif_recovery_hold_hours` 24 ·
  `notif_crushed_yesterday_threshold` 5
- **Vacation:** `vacation_default_days` 7 · `vacation_grace_wake` 58 ·
  `vacation_grace_decay_hours` 24 · `vacation_checkin_days` 14 · `vacation_max_days` 30
- **Rewards:** `coins_per_task` 10 · `streak_milestones`
  `{"fixed":[7,30],"thenEvery":50}` (JSON)
- **Observations (Number · wired July 23 2026, published):** `obs_window_days` 42 · `obs_replay_days` 90 ·
  `obs_day_cap` 3 · `obs_weekday_min` 15 · `obs_weekday_weeks` 3 · `obs_weekday_share`
  0.30 · `obs_timeofday_min` 20 · `obs_timeofday_dates` 5 · `obs_timeofday_weeks` 3 ·
  `obs_timeofday_share` 0.40 · `obs_margin_ratio` 1.5 · `obs_trend_half_min` 10 ·
  `obs_trend_ratio` 1.3 · `obs_trend_min_delta` 0.2 · `obs_trend_cooldown_days` 7 ·
  `obs_return_quiet_days` 14 · `obs_return_history_min` 5 · `obs_comeback_min` 8 ·
  `obs_comeback_dates` 3 · `obs_comeback_tasks` 3 · `obs_comeback_hours` 24 ·
  `obs_comeback_p75_hours` 48 · `obs_sticky_days` 14 · `obs_rundown_weekly_cap` 2
- **Weekly letter (Number · wired July 23 2026, published):**
  `letter_send_weekday` 1 · `letter_send_hour` 19 · `letter_max_beats` 3 ·
  `letter_quiet_max` 2 · `letter_rough_overdue_days` 4 · `letter_great_ratio` 1.5
- **Memory callbacks (Number · wired July 24 2026, published):** `callback_weekly_cap` 2 ·
  `callback_min_gap_days` 3 · `callback_min_age_days` 21 · `callback_fact_age_days` 7 ·
  `callback_best_day_min` 5 · `callback_streak_quiet_days` 14. The anniversary
  milestone set (1 week / 1 month / yearly) is deliberately NOT remote-tunable
  (calendar facts, not levers), and there is no repeat-cooldown key: the
  once-until-changed fact identity replaced it.
- **Suggested times (Number · wired July 25 2026, published):** `suggest_min_evidence` 15 ·
  `suggest_min_dates` 5 · `suggest_peak_share` 0.35 · `suggest_peak_window_min` 90 ·
  `suggest_peak_dates` 3 · `suggest_runner_up_margin` 0.10 · `suggest_series_min` 8 ·
  `suggest_series_dates` 5 · `suggest_list_min_series` 3 · `suggest_list_series_share`
  0.40 · `suggest_retime_mismatch_hours` 3 · `suggest_min_lead_min` 30 ·
  `suggest_dismiss_rearm_min` 60 · `suggest_reschedule_weight` 0.25. The runner-up
  center separation (3 circular hours) is deliberately NOT tunable - it is what makes
  the windows disjoint at the shipped ±90 width.
- **Weekday suggestion fallback (Number · wired July 27 2026, NOT yet created in the
  console):** `suggest_weekday_min` 4 · `suggest_weekday_dates` 3. A 42-day window
  holds at most 6 of any given weekday, so the floor must sit below that; 4 across 3
  dates is reachable yet meaningful. The fallback deliberately **reuses** the pooled
  `peakShare` (0.35) and `runnerUpMargin` (0.10) rather than adding its own, which is
  why this is two keys and not four.
- **Best Hours (Number · wired July 27 2026, NOT yet created in the console):**
  `bh_row_min` 5 · `bh_row_dates` 3 (a weekday row earns its capsule at 5 completions
  across 3 distinct dates) · `bh_second_wind_min` 5 · `bh_second_wind_dates` 3 (the
  evidence floor a secondary window must clear before Mochi names a second wind). The
  companion "share ≥ half the peak window's share" ratio (0.5) is deliberately a **code
  constant, not a key**, to hold the count at four.
- **Effort weights (Number · wired July 27 2026, NOT yet created in the console):**
  `effort_weight_tiny` 1.0 · `effort_weight_small` 1.4 · `effort_weight_medium` 2.0 ·
  `effort_weight_large` 3.0. The level→minute mapping stays code-fixed inside
  `EffortLevel`; only the weights are tunable.

**Deliberately not remote-tunable:** the buffer cap and treat/pet values (the widget
evaluates them without Firebase) and the 64-slot pending-notification cap (an iOS
platform fact).

### Outstanding external setup (user-owned, as of July 30 2026)

Console/account work no code change can do. The app degrades gracefully without
each item (shipped defaults, hardcoded fallbacks), so none block development -
but all block shipping.

- [ ] **Remote Config: create the 10 pending discovery-batch parameters**
  (Firebase console → Remote Config → publish). The first 74 were published
  and confirmed remote-sourced July 25 2026; the batch added
  2 `suggest_weekday_*`, 4 `bh_*`, and 4 `effort_weight_*` on July 27 2026,
  each listed above with its shipped default so behavior is unchanged until a
  deliberate tuning pass. `RemoteTuning.numberKeys` is the canonical list and
  the `consoleKeysMatch` test pins all **84** keys - run the suite after
  publishing to confirm nothing drifted, then launch a DEBUG build and confirm
  the startup audit logs `remote_tuning_audit all 84 keys remote-sourced`.
- [x] **`firestore.rules` moments block deployed** (Feature 6). Verified July 27
  2026 by diffing the console's live rules against the repo, byte-for-byte
  identical. All `firestore.rules` work is complete.
- [x] **firestore.rules: NO change needed for Feature 2** (decision, July 24
  2026): `bestStreakAchievedOn` rides the existing owner-scoped `users/{uid}`
  update rule like every other profile scalar; the spec pins its strict-exceed
  monotonicity client-side (`RewardsStore`), and unlike `adoptedOn` the field
  must keep advancing, so a write-once guard would be wrong. No redeploy.
- [ ] **App Store Connect: Paid Apps agreement + banking/tax.** Blocks ALL
  sandbox purchases until active - the single gate in front of live purchase
  testing.
- [ ] **App Store Connect: subscription review screenshots** for the two
  products (`mochi_2999_1y`, `mochi_399_1m`).
- [ ] **App Store Connect: App Store server notification URL** pasted in (from
  RevenueCat's dashboard) so renewal/cancellation events reach RevenueCat.
- [ ] **RevenueCat: upload the App Store Connect API key** (RevenueCat
  dashboard → project settings).
- [ ] **RevenueCat customer deletion on account delete** needs a server/Cloud
  Function holding the secret key - the client flow erases Firestore + Auth but
  cannot delete the RevenueCat customer (design-doc deletion step still open).
- [ ] **Firebase Authentication: enable the Google provider** (console →
  Authentication → Sign-in method) - Google Sign-In is fully wired client-side.
- [ ] **Legal URLs are placeholders** (`You/MochiLinks.swift`): privacy policy
  and support point at mochibuddy.app, which doesn't exist yet; EULA uses
  Apple's standard agreement. Swap when the site is live.
- [ ] **Purchase testing needs a physical device + Sandbox Apple Account**
  (simulator StoreKit is unreliable without a StoreKit config file).
- [x] **`firestore.rules` deployed July 24 2026** - adoptedOn write-once,
  letters/activityWeeks create-only contracts all live; letter composition
  confirmed working against the deployed rules.

**`vacation_grace_wake` derives from `mood_anchor` when unset** (v0.6.1): the wake target
is *defined* as the content anchor, so tuning the anchor alone moves the wake with it; an
explicitly published `vacation_grace_wake` still wins. The tuned values also reach their
user-facing surfaces: the "Mochi, shh · Nh" action label reads `notif_shh_hours`, and the
widget-mirror horizon tracks `notif_horizon_days`.

**Known deltas from the spec, all deliberate:**
- **Widget poses are code-drawn, not asset exports:** the shared Canvas pet view renders to
  a static image (`ImageRenderer`) marked `fullColor` for iOS 26 tinting. Same effect as
  the planned static assets with zero widget-only art; swaps for real exports when the
  commissioned poses land (roadmap #6). The doc's 6-mood set maps onto the current 4
  visual moods + sleeping until then.
- **Complete-from-widget queues in the App Group** (optimistically updating the snapshot)
  and the app persists it through the normal completion store on next open, coins
  included. Running Firestore inside the widget-intent process was rejected for the
  extension memory ceiling; consequence: the widget-completion celebration lands in-app
  at drain time rather than as a push, and the stored `moodForecast` field is the
  baseline curve (values, not bands) so the widget can add the live buffer itself.
- **The comfort buffer moved to the App Group suite** (with one-time migration), exactly
  as the data-model section planned; still device-local, never synced.
- **Large home widget and Watch remain out**, per the spec's own fast-follow scoping. The
  shared "framework" is a shared source folder compiled by both targets; a real framework
  target is a later refactor if a third consumer appears.
- **On-device use requires registering `group.com.aaronmckain.MochiBuddy`** in the Apple
  Developer portal (simulator ignores this); automatic signing handles the rest.
- The re-entry **bucket is computed at end time and held in UserDefaults** for the triage
  sheet rather than written as a `came_due_on_vacation` task flag; after re-entry the pile
  stresses the baseline again (the drift-to-true-mood behavior), so a persistent flag had
  no consumer. Revisit if multi-device triage ever matters.
- Vacation **entry UI is the existing toggle screen** (start recorded, picker defaults 7
  days, primer copy) rather than the full segmented-control bottom sheet; the empty-bucket
  "Welcome back" celebration beat is skipped silently for now.
- The **resting pose renders as the sleeping pose** until the commissioned art lands
  (roadmap #6), with its own distinct VoiceOver label so the two calm states never conflate.
- Re-lay triggers wired: foreground, every completion, editor saves, pet/treat, vacation,
  bedtime, prefs, entitlement change, notification actions, **timezone change** (v0.6.1;
  the orchestrator and widget mirror hold `.autoupdatingCurrent` calendars), and
  **`EKEventStoreChanged`** (2026-07-30, `.remindersChange` via the gateway's
  `onExternalChange`). The trigger list is now fully wired.
- **Celebrations are in-app only — there is no push celebration class** (v0.6.1). A
  milestone can only land on a completion, which happens with the app open or at
  widget-drain time on the next open; a celebration push would always arrive mid-session.
  The spec's "cute good-job notifications … for tasks completed from the widget" is
  served by the drain-time Home banner instead. `NotificationCopy.celebrationPool` is
  retained as the copy source if a push path ever ships.
- **Coin anti-farming (daily diminishing returns) is not implemented** — deliberate:
  open question #2 (the taper curve) is undecided, and the `dailyCoinsEarned` /
  `dailyCoinsDate` fields are reserved in the data model for when it is. Flat
  `coins_per_task` until then.
- **Notification imagery (expressive Mochi faces, intensity-capped) is not implemented**
  — gated on the commissioned pose set (roadmap #6). Interruption levels, thread
  coalescing, and copy voices shipped; attachments land with the art.
- Snooze targets: tonight = 19:00 (or an hour out if already evening), tomorrow = 09:00.
- Trial expiry mid-session is caught at flow entry / You-tab refresh, not by a live
  listener; consistent with "trial expiry is not an auth event."
- **Feature 1 (v0.7):** the `adoptedOn` write-once **rules-emulator test** is not in the
  suite — the repo has no Firestore-emulator harness yet; the rule itself is written in
  `firestore.rules` and must be **deployed** (`firebase deploy --only firestore:rules`).
  Client-side write-once is covered by tests. Also: `RestoreSuccessView`'s "Mochi's
  beaming again" line stays literal (that screen has no profile access pre-restore);
  the rename surface is a small sheet from the "Your Mochi" card per spec, and the
  one-time migration flag is device-local per-UID (a fresh device simply re-runs the
  idempotent presence-check backfill, same outcome).

### Known open bugs and follow-ups (not deliberate, not yet fixed)

Distinct from the deltas above, which are choices. These are defects or loose ends
found and recorded but not acted on.

- *(none currently open; the 2026-07-30 sweep below cleared the list)*

**Fixed 2026-07-30** (all six defects this section carried, validated by the full suite):

- **Widget-drained completions stamp one truthful time.** The widget queues the absolute
  tap instant (`PendingCompletion.tappedAt`) alongside the local context, and the drain
  threads it through to `completedAt` (entries queued by an older version reconstruct it
  from the local context via `approximateInstant`). A stale tap can no longer book into
  today's momentum window, and day-bucketed consumers agree with `completedLocalDate`.
  The streak also credits the *tap* day and never regresses newer activity. Pinned by
  `drainLands`, `approximateInstantRoundTrip`, `drainedTapCreditsTapDay`,
  `staleDrainNeverRegresses`.
- **The drain and the first refresh are sequenced.** `WidgetCompletionDrain` memoizes its
  in-flight drain so concurrent callers coalesce; `HomeViewModel.refresh()` awaits the
  drain before its first read, `RootView.enteredHome()` starts the drain ahead of its
  network awaits, and Home also refreshes on `scenePhase == .active` (onAppear never
  re-fires on a resident view). A signed-out drain now preserves the queue instead of
  losing taps. Pinned by `refreshDrainsWidgetQueueFirst`, `concurrentDrainsCoalesce`,
  `signedOutPreservesQueue`. `TaskCompletionStore` also gained a session-scoped
  completion guard: a stale row tapped after the drain (or another surface) already
  landed it is a full no-op - no second coin award, no duplicate spawned occurrence, no
  `completedAt` overwrite (an undo re-arms it). Cross-device stale rows remain the one
  unguarded path; that needs listeners (roadmap). Pinned by `duplicateCompleteIsNoOp`,
  `undoRearmsAward`.
- **The entitlement horizon caps on `willRenew`, not on expiry.** `MembershipStatus`
  carries `willRenew` (populated from RevenueCat); the orchestrator drops the expiry cap
  when auto-renew is on, so sandbox's hourly renewals and every converting trial plan the
  full horizon, while a real cancellation still caps. Pinned by `willRenewUncapsHorizon`
  (with `staleExpiryDoesNotCap` still pinning the past-expiry case).
- **A lapsed streak zeroes on open.** `RewardsStore.zeroLapsedStreak` writes the zero on
  Home's first refresh when a day was genuinely missed; the record and `lastActiveDate`
  are untouched, and the vacation and membership-lapse freezes still never zero. Pinned
  by `lapseZeroes`, `aliveYesterdayKept`, `zeroStreakNoOp`, `staleStreakZeroesOnRefresh`,
  `membershipLapseFreezesStreak`, `vacationFreezesStreak`.
- **`EKEventStoreChanged` is wired** as a re-lay trigger (`.remindersChange`):
  `EventKitRemindersGateway` observes its own store, refreshes sources, and fans out via
  `onExternalChange` in `AppContainer`. View freshness rode along: the reminders list
  detail refreshes per appearance (was once per lifetime), and Tasks and ListDetail
  re-fetch on foreground. Note the mood-engine *union* of native + Apple tasks remains
  unbuilt (see the integration spec); the trigger is honest plumbing that becomes
  load-bearing when the union lands.
- **`AccentColor.colorset` has a value**: ube `#7B4BC4` for light, Black Sesame lavender
  `#C9A6FF` for dark, so system chrome (alerts, share sheets) stops falling back to
  default blue.

---

## The one-liner

A todo app where your reminders are tied to the wellbeing of **Mochi**, a cute
pet who reflects how on-top-of-things you are. Stay on track and Mochi is happy.
Fall behind and Mochi gets uneasy, then anxious, then very sad — a gentle,
glanceable nudge to take care of your tasks (and, by proxy, yourself).

## Product philosophy

- **Subscribe once, get everything.** No microtransactions, no cosmetic store,
  no à-la-carte unlocks. Every theme, widget, and feature is included in the
  subscription.
- **Coins are earned, never bought.** They exist to convert *productivity into
  comfort for Mochi* — not to be a paid currency.
- **Delight-forward, guilt-light.** Mochi is a companion you help, not a warden
  who punishes you. The upside carries as much weight as the downside.
- **14-day free trial (yearly plan only), then subscription. No freemium tier.**
  The emotional hook needs a few days to land (you have to fall behind once and
  feel Mochi react), so the trial gives the full experience before the ask.
  (Extended from 7 to 14 days, Aug 2 2026; the monthly plan carries no intro
  offer.)

## The feel

Soft, warm, tactile. Rounded shapes, squishy motion, satisfying haptics, cute
sounds. Cozy over corporate. Mochi's mood is readable in a fraction of a second.

---

## Mochi & the mood system

A spectrum, not a binary. Draft states:

1. **Ecstatic / celebrating** — you're ahead, crushing tasks
2. **Happy** — baseline, on track
3. **Content** — neutral, quiet
4. **Uneasy / fidgety** — starting to slip
5. **Anxious / nervous** — overdue tasks piling up
6. **Overwhelmed / very sad** — the floor state

**Locked decisions:**
- **The sad floor is genuinely sad** — not a guilt trip, but real emotional weight.
- **Mochi never dies and never permanently degrades.** Floor is "very sad"; any
  positive action visibly lifts him.
- **Single approach, no intensity slider.** Keeping it simple. (Adjustable
  intensity is a *possible* scope addition much further down the line.)
- **The upside must hit as hard as the downside** — celebrations, happy dances,
  cute noises when you accomplish things.

### Mood algorithm (formal spec)

Mood is a continuous value `V` on a 0–100 scale, mapped to the six states, then
split into **baseline** (from tasks) and a **comfort buffer** (from pets/treats).

**Bands:** very sad 0–15 · anxious 15–35 · uneasy 35–50 · content 50–70 ·
happy 70–88 · ecstatic 88–100.

**Guiding principles:**
1. **Volume ≠ stress.** Only *overdue* (and optionally *imminent*) tasks generate
   stress. On-time tasks and undated tasks contribute **zero**. 20 on-time tasks
   = a calm Mochi.
2. **Stress saturates.** Contributions sum, then pass through a saturating curve,
   so the first overdue tasks matter most and Mochi can never drop below very sad.
3. **Momentum is gated.** Completions lift mood only when overdue stress is low —
   you can't fake happiness while behind. You fix it by clearing the overdue tasks
   (which removes their stress directly).
4. **Buffer is temporary and capped.** Pets/treats add a decaying lift on top,
   never touching the baseline.

**Constants (starting values — all tunable):**
`A = 58` (content anchor) · `H_MAX = 48h` (lateness cap) · `BASE = 0.4` (instant
sting when a task first goes overdue) · priority weights `low 1.0 / med 1.5 /
high 2.0` · `TAU_S = 4` (stress saturation) · `P_UP = 42`, `TAU_M = 2.5`
(momentum) · `GATE_K = 20` (momentum suppression) · `BUFFER_CAP = 30`.

**Per overdue task i:**
`lateness_i = min(1, hours_overdue_i / H_MAX)`
`c_i = priority_weight_i × (BASE + (1 − BASE) × lateness_i)`
*(Optional imminent tasks due within ~3h, not done: add a small `0.15 × weight`
term. Omit for v1 if simpler.)*

**Aggregate:**
`R = Σ c_i`
`stress = A × (1 − e^(−R / TAU_S))`
`momentum = P_UP × (1 − e^(−completions_24h / TAU_M))`  *(+ streak bonus)*
`gate = clamp(1 − stress / GATE_K, 0, 1)`
`baseline = clamp(A − stress + momentum × gate, 0, 100)`

**Comfort buffer** (decays over time, not part of baseline):
each pet ≈ `+8` (fast decay, ~15 min), each treat ≈ `+20` (slow decay, ~2–3h),
total buffer clamped to `BUFFER_CAP`.
`displayed = clamp(baseline + buffer, 0, 100)`

**Smoothing:** the *displayed* value eases toward its target (rate-limited / lerp)
so the mood drifts rather than snapping — no flicker on every edit.

**Worked examples** (medium priority, ~24h overdue each, 1 recent completion):

| Overdue | baseline `V` | state |
|---|---|---|
| 0 | 58 (+momentum) | content → happy |
| 1 | ~45 | uneasy |
| 2 | ~34 | anxious |
| 5 | ~16 | very sad (edge) |
| 10 | ~4 | very sad |
| 20 | ~0 | very sad (pegged) |

**Edge cases:**
- No tasks at all → `content` (calm), not sad. Nothing is wrong.
- Just cleared the whole list → momentum spike → `ecstatic`, decaying to content.
- Undated tasks → never overdue → never stress Mochi.
- **Sleep:** stress isn't recomputed into visible mood overnight; on wake, baseline
  reflects reality but a small morning-grace buffer softens the landing.
- **Vacation mode:** freeze baseline / suppress stress accrual + notifications. See the
  full *Vacation mode* section for the freeze-and-triage mechanics and re-entry.

---

## Sleep & night

- Mochi **sleeps during the user's quiet hours** (configurable bedtime window).
- **Sleep pauses expression and notifications — it does NOT reset the backlog.**
  If you go to bed drowning in overdue tasks, you wake up still behind. Otherwise
  people would just wait out the night to dodge the stress.
- **Small morning grace:** Mochi wakes a little groggy but not instantly panicking
  — a gentle "fresh start" beat each morning. A buffer, not an erase.
- No anxious pings at 2am — sleep naturally enforces quiet hours.
- Late-night task completion earns a sleepy little happy reaction.
- **Bedtime is set during onboarding** (a sensible default), changeable later in
  settings.
- **Morning wake-up rundown:** when Mochi wakes, he sends a friendly notification
  with the day's **top 1–3 priorities** — a daily briefing from your pet, not a
  nag. Keep it short and supportive; tone can flex to the load ("light day!" vs.
  "big one today — we've got this").

---

## Core loop

Add tasks → live your life → Mochi's mood tracks your progress → completing tasks
makes Mochi happy *and* earns coins → coins + pets keep Mochi comfortable →
widgets keep Mochi (and your tasks) glanceable all day.

---

## Calming: the baseline + comfort-buffer model

Two layers:

- **Baseline** — a pure function of your reminder state (overdue count, load,
  procrastination). This is the mood Mochi always *drifts back toward* — his
  gravity.
- **Comfort buffer** — a temporary positive lift *on top of* the baseline, added
  by petting or treats. It **decays over time back down to the baseline.** It does
  not move the baseline.
  - **Petting** — free, instant, small lift, **fast decay.** Buys a little time.
  - **Treats** (bought with earned coins) — bigger lift, **slower decay.** Buys
    more time.

**Only completing tasks moves the baseline.** Pets and treats just delay the slide
back. Petting buys time; finishing is the cure.

**Self-limiting economy:** coins come only from completing tasks, so the only way
to afford lots of treats is to have been productive — meaning your baseline is
probably healthy anyway. Nobody can ignore everything and treat-spam their way to
a happy Mochi. (If playtesting ever shows abuse, add gentle diminishing returns on
stacked buffers — but likely unnecessary at launch.)

---

## Currency (coins)

- **Earn only** — never purchasable. Sources: completing tasks, streaks, daily check-in.
- **Flat rate per task** — all tasks earn the same. *Not* scaled by priority, since
  priority-scaling would just make people mislabel everything "high" to farm coins.
- **Coins still awarded for completing overdue tasks.** Clearing a late task is the
  recovery moment we most want to reward — the "penalty" for lateness is already
  paid via the low baseline + extra notifications while it sat overdue.
- **Anti-farming:** flat-per-task shifts the exploit from "inflate priority" to
  "spam trivial tasks." Blunt it with **gentle daily diminishing returns** (first N
  completions pay full, then taper) rather than a hard cap. Optional: a task must
  exist for a few minutes before it pays, to stop create-and-instantly-complete.
- **One sink: treats** that comfort Mochi. No cosmetic store, so keep the economy
  *modest and delightful* — variety and favorites, not power tiers.

### Treat economy — duration, not magnitude

**Key constraint: the buffer is capped (30), so magnitude is a bad differentiator.**
A +20 treat isn't meaningfully better than a +14 one once you hit the ceiling.
**Price treats by how long the comfort lasts.** Every treat must also strictly beat
the *free* pet, or nobody buys it.

| Item | Lift | Duration | Cost |
|---|---|---|---|
| Pet | +8 | ~15 min | free |
| Sweet berry | +15 | ~1 hr | 15 |
| Dango | +18 | ~3 hr | 30 |
| Cupcake | +20 | ~6 hr | 55 |

- **Buy = give.** No treat inventory/ownership system (avoids a whole subsystem).
- **No "mystery box"** or random-reward treats — a gacha mechanic attached to an
  anxious pet is off-brand for a no-manipulation app.

---

## Themes, widgets, features — all included

- **Themes:** user-swappable palettes (orange, pink, green, …) recoloring the whole
  UI + Mochi's environment. Seasonal drops as recurring content. All included.
- **Widgets:** small (Mochi's face/mood), medium (Mochi + next task), lock screen
  (mood + next task), stretch: Watch complication. All included.
- Everything ships with the subscription.

---

## Notifications

> 🆕 **v0.4 — RESOLVED** (was ON HOLD). Architecture and cadence locked in v0.3; copy, exact
> constants, actions, winback, instrumentation, the mood-ping technical requirements, and a
> dev inspector tab all resolved below.

**Architecture: fully local / on-device. No server.** We explicitly considered a
server-side mood engine that pushes reactively and rejected it: it would require a
*duplicate* engine (Swift + Cloud Functions) kept byte-identical forever, it structurally
can't see the device-local comfort buffer (so it'd contradict the visible mood), and the
escalation it was meant to enable is bounded anyway. Local notifications work offline, on a
plane, and when the backend is down. *(Possible far-future supplement: a silent
`content-available` push as an "alarm clock" that wakes the app to re-lay its own schedule —
server as alarm clock, never as brain — only if analytics show a dormant-user gap.)*

### Two classes, two budgets, two toggles

**Promises** — due-soon / overdue. User-requested, task-specific, **exact**, **uncapped**,
`.timeSensitive`. **Never** mood-driven. Recurring task → one repeating trigger (1 slot).
Sacred: a reminders app that drops a reminder is broken.

**Mood pings** — ambient, **vague**, capped, `.passive` (never punches through Focus/DND).

### Cadence — escalate at the floor, with brakes

| State | Mood pings/day | Min spacing | Tone |
|---|---|---|---|
| Ecstatic / Happy | 0–1 | — | Celebration / streak |
| Content | 0 | — | Silence |
| Uneasy | 1 | — | Gentle, hopeful |
| Anxious | 2–3 | 3h | Concerned, warm |
| **Very sad** | **4** | **2h** | **Soft, sad, never shaming** |

Hard ceiling **4/day** · always **coalesced** (5 overdue = 1 ping) · sleep enforces quiet
hours · **recovery is instant** (one completion drops the state and its cadence).

**Three brakes make escalation safe.** *The risk:* the person at the floor is fragile and
can permanently kill notifications in one tap — an irreversible loss of the whole channel.
1. **Acute vs. chronic.** Volume escalates with *depth* but decays with *duration*.
   **Taper after ~3 consecutive days at the floor** → 1/day, and shift copy from nudging to
   presence ("no pressure — Mochi's just here"). Day 1 at the floor is a bad day; day 7 is
   burnout, and hammering it is how you get deleted.
2. **Tone never tracks volume.** Every line stays soft — Mochi is sad *with* you, never *at*
   you. "Mochi's having a hard day too" ✓ / "You've ignored 6 tasks" ✗.
3. **An in-app valve that isn't the nuclear option.** Every escalation ping carries a
   **"Mochi, shh — 24h"** action; plus per-category toggles (task reminders / morning
   rundown / mood dips, each independently off-able) and vacation mode. The easiest way to
   quiet Mochi must never be iOS's system-level off switch.
   > 🆕 **2026-07-21 — dial removed.** The originally specced "how chatty is Mochi" dial
   > (Quiet / Normal / Chatty) shipped, then was cut by product decision: one cadence (the
   > old Normal table) for everyone, no granularity beyond the category toggles. `NudgeLevel`
   > and the stored `level` pref are gone from the code; stale `level` fields in existing
   > Firestore docs are ignored on decode.

### Scheduling model (local, predictive)

Enabling property: **mood only falls on its own; it rises only when the user acts — and
acting means the app is open, which is exactly when we re-lay the schedule.**

- **Predict pessimistically** (assume zero completions), pre-schedule for the predicted band
  crossings + cadence, then **re-lay** on: app foreground, task add/edit/complete/snooze,
  widget App Intent, timezone change. A prediction can only be wrong in the direction where
  the app is open to fix it.
- **Stable IDs** — `due-{taskId}`, `mood-{state}-{fireTime}`, `rundown-{date}` — so re-laying
  wipes and rewrites **mood** pings without ever touching a **promise**. Never nuke-and-
  rebuild (you'll drop a reminder).
- **Budget priority over the 64-slot cap:** promises by nearest due → mood pings →
  rundowns → weekly letter (🆕 v0.7 — the letter drops first under pressure; it alone
  has a full in-app backstop. See *The Personal Layer → Feature 3*).
- **Mood copy stays vague — staleness insurance.** A ping scheduled last night fires on last
  night's prediction; "Mochi misses you" survives being stale, "3 tasks overdue" doesn't.
  (Only real staleness sources: another device, or completion in Apple's own Reminders app —
  both narrow.)
- **Dormant users are perfectly predictable** (no completions = prediction exactly correct),
  so escalation works *best* on exactly the users it targets. Extend their horizon to ~7–10
  days + one repeating backstop trigger so nobody falls off the edge.
- **Denied permission →** provisional auth as the floor; the widget carries the app.
- Cadence constants live in **Remote Config**.

### Morning rundown

Its **own class** — does **not** count against the 4/day mood cap. Once daily at wake.
Ranking for "top 1–3": overdue (lateness desc) → due-today-with-time (time asc) →
due-today-no-time (priority desc). Tone flexes to load; length does not (always ≤3).
Respects the task-name privacy setting.

### Celebrations

**No per-completion push** — completing a task happens with the app open, so delight is
**in-app** (animation, sound, coin). Cute "good job" notifications are reserved for when
they'd land *later or elsewhere*: **streak milestones**, a next-morning "you crushed
yesterday" folded into the rundown, and tasks **completed from the widget** (app closed).

### Copy & voice — RESOLVED

> 🆕 **v0.4.** Three notification classes, three non-negotiable voices.

- **Mood pings = Mochi's monologue, blame-free, never a task name.** "Mochi's missing you" ✓ /
  "Mochi feels neglected — come back!" ✗ (points a finger). They never name a task, both for
  voice *and* because they fire on a prediction made hours earlier (a named task might already
  be done; a feeling can't go stale).
- **Reminders + morning rundown = always name the task(s).** Being specific is their whole job.
- **Celebrations = always celebratory.**
- **Copy library:** ~6–8 lines per escalating state, 4–5 per celebration, round-robin with a
  "don't repeat the last N" guard. Ship test: *would this make a fragile person at the floor
  feel worse?* If yes, cut it. **Floor copy is two pools:** acute (day 1–2 — gentle, hopeful)
  and chronic (day 3+ — pure presence, zero ask). The taper changes the *words*, not just the
  frequency.
- **Emoji: sparingly, celebrations only.** Never on sad/floor copy (tone-deaf, and VoiceOver
  reads it aloud).
- **Task-name privacy:** names show on the lock screen **by default** (normal for a reminders
  app), with an **opt-in "hide task names on lock screen"** toggle (off by default). This is
  also the lock-screen privacy answer; mood pings are already nameless.
- Localization-ready from day one: full-sentence String Catalog keys, no concatenation.

### Cadence & celebration constants — RESOLVED

> 🆕 **v0.4.** Cadence table unchanged; taper and its guards locked. All values Remote Config.

- **Floor taper = gentle ramp:** day 1 = 4 pings, day 2 = 3, day 3 = 2, **day 4+ = 1/day
  indefinitely**; copy shifts acute → chronic across the same ramp.
- **Taper resets only on a genuine recovery** (climb to a good band and hold). A momentary
  blip — one task done, mood pops up, slides back overnight — **does not** reset it. *Resetting
  on a blip would give the person who managed one task on a bad day* more *pings the next day
  than if they'd done nothing — punishing effort, the inverse of the whole philosophy.*
- **No entry grace — mood pings fire on band crossing.** *Known tradeoff:* you'll occasionally
  get a gentle ping for a dip you were already fixing. **Bounded** by the caps (uneasy is
  1/day, all coalesced), so worst case is one soft nudge on a day you'd handled.
- **Streak celebrations (sparse): 7, 30, then every 50 days.** *Consequence to design around:*
  a new user's first celebration ping is a week out, so the **in-app** day-1/day-2 delight
  (check-off animation, sound, coin) must carry the early upside alone.
- **"You crushed yesterday" beat folded into the next morning's rundown** when the prior day
  was notably productive — **not a separate ping** (no slot, no noise). Fills the gap between
  sparse streak trophies so the upside stays present.

### Actions & richness — RESOLVED

> 🆕 **v0.4.**

| Notification | Actions |
|---|---|
| **Reminder** | Complete · Snooze (menu: **1h / tonight / tomorrow**) |
| **Mood ping** | Pet Mochi · **"Mochi, shh — 24h"** |

- **Pet lives on mood pings, not reminders** — keeps reminder button-count within iOS's limited
  action slots while the snooze menu takes the rest.
- **All actions run as background App Intents** (app never opens): Complete removes stress,
  Snooze pushes the due date **and increments the reschedule counter** (feeds the v2
  procrastination signal), Pet bumps the buffer. **Every action re-lays the schedule + reloads
  the widget.**
- **Images — expressive faces everywhere, intensity-capped on predicted pings.** Mood pings
  carry an expressive face but capped at "a bit down," **never full floor-state sobbing** — so
  a stale predicted ping is a forgivable miss, not a jarring lie. The most extreme expressions
  are reserved for **in-app** (always live/accurate) and **celebrations** (real events).
- **Interruption levels:** reminders `.timeSensitive` · mood pings `.passive` · rundown
  `.active` · celebrations `.active`. Mood pings share a `threadIdentifier` so they coalesce.

### Winback & instrumentation — RESOLVED

> 🆕 **v0.4.**

- **Winback (lapsed): pure functional — reminders only.** Real due/overdue reminders fire
  indefinitely (already locked) and carry **zero** come-back nudge — no "we miss you," no
  Mochi, no guilt. The winback *is* the app quietly staying useful. Strictest read of
  "manufacturing guilt is not fair": a lapsed user is never made to feel worked-on.
- **Instrumentation:** log every notification event **tagged with mood state at fire time** —
  delivered, opened, action, and the two that matter most, **permission-revoked** and
  **uninstall** (proxied by token invalidation / last-seen), segmented by mood state. This
  validates the escalate-at-the-floor bet cheaply. **Never log task titles.**
- **Tripwire = alert-only to start.** When floor-state revocation/uninstall exceeds baseline,
  **flag it for a human decision** rather than auto-throttling — early data is too thin to
  safely automate a cadence change. Revisit auto-throttle once a baseline exists. Pair with the
  **daily mood-state distribution** (roadmap #7).

### Mood pings: technical requirements — RESOLVED

> 🆕 **v0.4.** The one notification class that must fire *correctly about the future* while the
> app isn't running.

**The consistency invariant:** *a fired mood ping must never contradict `mood(now)` on next
foreground.* Guaranteed **by construction, not synchronization** — there is one deterministic
`mood(t)` sampled at two times (scheduling computes `mood(fireTime)` from the current snapshot;
opening computes `mood(now)`), so they agree with zero reconciliation. Nothing is kept "in
sync"; a notification is a *pre-evaluation* of the one curve.

**Forecast input model — simulate deterministic app-closed events.** The forecast is *not* just
"current tasks aging." `mood(t)` must bake in every deterministic change to its inputs that can
happen while the app is closed: future-dated tasks crossing into overdue, **recurring-task
roll-forward + re-stamp** (which re-caps that task's lateness rather than letting it grow),
**vacation auto-expiry**, and it must **cap the mood-ping horizon at the locally-known
entitlement expiry** so no mood ping fires into a `lapsed` state. In a no-action forecast none of
these push mood *up*, so the curve is **monotonically non-increasing until saturation** → each
band boundary is crossed **exactly once** → scheduling = find ≤3 crossings, lay cadence between
them.

**Core requirements:**
- **One engine, parameterized by time.** No second predictor implementation; drift between a
  forecast path and the on-open path is the only way to break the invariant.
- **Forecast the *displayed* value** (`baseline(t) + buffer(t)`, buffer decay simulated). Buffer
  rises only on a pet/treat → re-lay; **petting from the widget must trigger a re-lay.**
- **Cadence generation honors four constraints at once:** per-state daily count, min spacing,
  the global 4/day ceiling, and quiet-hours suppression (fire times in the sleep window are
  **dropped, not shifted** — no dawn dump). One mood ping per instant.
- **Budget after promises, soonest-first,** into the remaining 64 slots; reserve one slot for a
  repeating backstop for dormant users; degrade to zero mood pings under promise pressure (the
  widget carries).
- **Longest horizon for dormant users** (~7–10 days) — their forecast is exactly correct.
- **Re-lay = scoped wipe-and-rewrite of `mood-*` IDs only,** never touching a `due-*` promise;
  idempotent; **debounced** against mutation storms.
- **Suppression composes** (shh-24h, vacation, quiet hours, lapsed) — mood pings only, never a
  promise, and **none reset the taper counter.**
- **Degrade, don't disable, on denied/revoked permission** — keep scheduling; provisional/quiet
  delivery; re-check settings on foreground.

**Re-lay triggers (exhaustive):** app foreground · task add/edit/complete/snooze/delete · widget
App Intent (pet/complete) · treat purchase · timezone change · bedtime/quiet-hours edit ·
vacation toggle · "shh — 24h" · Remote Config fetch · entitlement change · `EKEventStoreChanged`.

**Edge cases (selected):** floor entered at 03:00 during quiet hours still counts as day-1
(taper counter is by first floor-entry calendar day) · recurrence roll while closed is
simulated, not mis-predicted · a happy/ecstatic mood ping coincident with a streak celebration
**yields to the celebration** (no double-notify) · buffer that lifts displayed mood up a band
delays the crossing predictably · "shh — 24h" expiring at the floor resumes at the *tapered*
cadence, not day 1 · null quiet-hours window is never allowed (always fall back to default).

**Named accepted limitations (v1):** cross-device double mood ping (buffer is device-local) ·
external-completion staleness (Apple Reminders / other device — *why* the copy is vague and
imagery is capped) · device clock is trusted. Deliberate boundaries, listed so they aren't
rediscovered as bugs.

### Dev tool — notification scheduler tab

> 🆕 **v0.4.** A **`#if DEBUG`-only** tab in "You" that makes the predictive scheduler
> inspectable and the consistency invariant *falsifiable at a glance*.

- **Gating:** compiled behind `#if DEBUG` — **physically absent from the release binary**, not
  merely hidden. Entry row at the bottom of "You," debug builds only. No production gesture.
- **Timeline chart (centerpiece):** the pending queue plotted on a time axis, overlaid on the
  live `mood(t)` forecast curve, band threshold lines, shaded quiet-hours + suppression windows.
  Notifications colored by class (promise / mood / rundown / celebration / backstop). A mood dot
  **not** on a band crossing, or a dot inside a quiet-hours band, is a *visible* bug.
- **Header state:** slot meter `used / 64` by class · displayed mood (+ raw `R`, `stress`,
  `momentum`, `gate`, per-task `c_i` on tap) · buffer decay timers · taper state · horizon end +
  *why* · entitlement state.
- **Per-notification detail:** stable ID, class, fire time (abs + relative), interruption level,
  thread id, trigger type, scheduled copy + attachment (with a **staleness flag**), predicted
  state/value for mood pings, linked task + source for promises.
- **Re-lay log:** timestamp · trigger · mood pings wiped vs. rewritten · duration (ms) · debounce
  indicator.
- **Live consistency checks:** the **invariant** (does each pending `mood-*`'s baked-in state
  equal `mood(fireTime)` recomputed now?) · slot reconciliation vs.
  `getPendingNotificationRequests()` · orphan check (past-dated pending mood pings).
- **Actions:** force re-lay · dump pending JSON (optional title redaction) · fire selected now ·
  clear `mood-*` / clear all · toggle quiet hours / vacation to preview · **time-travel**
  (simulated "now" for preview only — never touches the real queue).
- **Out of scope:** not user-facing, not localized, not a11y-audited to product standard,
  stripped from release. Exists to validate the invariant, the cadence constraints, the budget
  order, and the re-lay scoping cheaply and visually.

---

## Art direction: animation & sound

**Recommendation: fully animated, rig-based — not static images.** Mochi being
*alive* is the entire product; a static sad PNG can't do what a drooping, sniffling,
then-brightening little creature does. This is the one place not to cut.

Keep it affordable by using **skeletal / state-machine animation** (strongly
consider **Rive** — its state-machine model maps 1:1 onto Mochi's moods +
reactions, it's lightweight on mobile, and it responds to touch in real time so
petting can react live). Alternatives: Lottie (great for canned reactions, less
interactive), Spine/DragonBones (game-style).

**Launch scope to stay sane:** ~6 mood idle loops + a handful of key reactions
(pet, task-complete celebration, fall-asleep, wake-up, receive-treat). Add more
reactions over time. **Themes recolor the same rig** — palette swaps, not new
animation — so themes don't multiply the art work.

**Sound:** per-state ambient cues, purring when petted, sleepy sounds at night,
celebratory chirps. Never rely on sound alone (many users mute) — animation carries
the emotion.

**Freelancing the animation:** this is a well-bounded commission, which keeps it
affordable — hire someone who knows **Rive** specifically (so you get the
interactive state-machine wiring, not just static art), or split it: a character
designer for Mochi's look + a Rive animator to rig and animate. Look for "Rive,"
"Lottie," or "app mascot animation" portfolios. **This design doc + the mood-model
diagram *is* the brief** — the tighter the spec, the cheaper and cleaner the job.
Make sure the contract hands you the **source files** (the `.riv` / rig), not just
exports.

---

## Task management (v1 — deliberately lean)

Every field earns its place by being useful *or* by feeding Mochi's mood. No bloat.

**A task is:**
- **Title** (required)
- **Due date + optional time** — the mood-critical field. No due date = it never
  stresses Mochi (just a someday todo).
- **Priority: low / medium / high** — this *is* the mood weight (1 / 1.5 / 2).
- **Notes** (optional)
- **Repeat** (optional): none / daily / weekdays / weekly / monthly / custom
  interval. Completing an occurrence spawns the next.
- **List** (optional; defaults to Inbox). The personalization step can seed a couple
  (Work, Personal…).
- *(internal)* **reschedule count** — stored now, powers the v2 procrastination signal.

**Core interactions:**
- **Fast capture** — title + optional when/priority in one sheet. Speed matters.
- **Complete** — satisfying check-off → Mochi reacts happily + coin. The dopamine beat.
- **Snooze / reschedule** — pushes the due date; increments the reschedule counter.
- **Overdue** tasks surface at the top and drive Mochi's mood.

**Views:** Today (default) · Upcoming · Lists · Completed.
**Home screen** = Mochi (mood + tap to pet) + coin balance + Today's tasks + quick-add.

**How it feeds the mood engine:** due date/time → overdue + lateness · priority →
weight · completion → removes stress at the source + coins + momentum · reschedule →
future procrastination signal.

**Explicitly NOT in v1 (the anti-bloat list):** subtasks/checklists, tags beyond
lists, dependencies, file attachments, location reminders, collaboration/sharing,
time tracking, custom fields. A simple checklist could come later without touching
the mood engine.

### Recurring tasks (mood-engine invariant)

> 🆕 **v0.3 — RESOLVED.** The rule that stops one neglected habit from flooring Mochi.

- **One live occurrence, ever.** A recurring task never stacks. The current occurrence
  stays live and accrues lateness until it's completed *or* the next occurrence comes due
  — at which point it **rolls forward** and the previous one is marked missed.
- **Rolled-forward occurrences are re-stamped** with the new due date, so lateness never
  exceeds **one period**. This falls out for free: a neglected *daily* high-priority habit
  sits at ≈24h late → `c ≈ 1.4` forever (mild, present, never snowballs); a *weekly* task
  rolls after 7 days, passes the 48h `H_MAX` cap, and reaches full `c = 2.0`. Bigger
  commitments hurt more when dropped — no hand-tuning needed.
  - *Rationale:* for a recurring task the live item genuinely **is** today's. Monday's
    vitamins aren't takeable on Wednesday — the occurrence expired, it wasn't deferred.
    Showing "3 weeks overdue" is a category error (renders a habit as a to-do) and invites
    the user to *delete* the task to make the shame go away. Re-stamping is honest about
    what completing actually does, and keeps guilt out of the UI.
- **Completion semantics: calendar-anchored (fixed) by default.** Complete a
  weekly-Tuesday task early on Sunday → next is still Tuesday. Matches Apple Reminders, so
  imported tasks behave consistently. A **"repeat from completion date" (floating)**
  per-task toggle — for interval self-care like "water plants every 3 days" — is
  **post-v1**.
- **Missed occurrences are logged silently** (`originalDueAt` + a missed log retained),
  feeding streaks and the v2 procrastination signal. **Never** surfaced as a "Missed" list
  — that's a guilt ledger. May later appear only as *positive* stats ("vitamins: 18 of 30
  days").
- **Abandoned-habit auto-pause** ("haven't done this in 3 weeks — pause it?") = **v1.1**,
  not v1. For now an ignored habit keeps its steady, bounded hum.
- **Notification bonus:** an infinite daily/weekly repeat = **one** iOS repeating trigger
  = **one** of the 64 pending-notification slots.

## Timezones

- **Store timestamps in UTC** (Firestore Timestamps already are). So yes — store in UTC.
- **But timed reminders are wall-clock intentions, not fixed instants.** Treat a
  task's time as wall-clock in the user's *current* timezone: "5:00 PM" fires at 5pm
  wherever they are. Store the intended local time + origin timezone alongside the UTC
  instant and re-interpret on the current device.
- **Date-only tasks** carry no time/zone — a calendar date; overdue flips at the end
  of that local day.
- **Overdue** is evaluated against device-local "now."
- **Bedtime / quiet hours** follow the device's current local timezone (Mochi sleeps
  at your local night, wherever you are).
- **Bug this avoids:** storing a fixed UTC instant and firing it literally → a "5pm"
  reminder that goes off at 2pm after flying west.

## Data model (Firestore)

Everything under the user's own document; security rules restrict each user to their
own subtree.

`users/{uid}`
- `displayName`, `authProvider`, `createdAt`
- `mochiName` (default "Mochi"; sanitized at every persistence boundary), `adoptedOn`
  (date-only `YYYY-MM-DD`, stamped at the naming beat; write-once, enforced by
  security rules; distinct from `createdAt` — 🆕 v0.7, see *The Personal Layer →
  Feature 1*)
- `observationIntervals` — append-only log of vacation + lapse intervals (🆕 v0.7,
  Feature 4: momentum eligibility; synced because deterministic hysteresis needs
  identical inputs on every device)
- `timezone` (IANA, current), `bedtimeStart`, `bedtimeEnd`
- `themeId`, `interests[]`
- `coins`, `dailyCoinsEarned`, `dailyCoinsDate` (diminishing-returns cap)
- `streakCount`, `lastActiveDate`, `bestStreakAchievedOn` (🆕 v0.7, Feature 2:
  date-only, streak-engine calendar semantics, updated **atomically with
  `bestStreakCount` and only on strict exceedance** — equal never overwrites;
  legacy profiles are never assigned a guessed date and get count-only copy until
  a new record stamps it)
- `isSubscribed`, `trialEndsAt` (mirrored; RevenueCat is source of truth)
- `notificationPrefs`

`users/{uid}/lists/{listId}` — `name`, `color`, `icon`, `order`

`users/{uid}/letters/{letter-{periodStart}}` — 🆕 v0.7 (Feature 3): period contract
(`periodStart`, `periodEndExclusive`, timezone), classification, beat types + line
ids, **both rendered variants** (full + private), pet-name snapshot, composed-at,
provenance (composer/copy-deck versions, non-reversible summary hash), `readAt?`.
**Create-only by security rules** (`readAt` is the sole mutable field); letters are
immutable postcards, synced across devices, destroyed with the subtree.

`users/{uid}/activityWeeks/{periodId}` — 🆕 v0.7 (Feature 3): create-only weekly
engagement marker, written on the first user-visible foreground session in the
period (notification taps count; background refresh / scheduling / widget drains do
not). The deterministic arbiter of letter dormancy — product data, never Analytics.

`users/{uid}/moments/{naturalKeyId}` — 🆕 v0.7 (Feature 6): append-only Journal
moments. **Ids identify events, not categories:** `adoption-{adoptedOn}` ·
`anniversary-{tier}-{occurredOn}` · `streak-milestone-{count}-{occurredOn}` ·
`vacation-return-{intervalId}` · `list-return-{listId}-{sourceEventId}`. Fields:
type, `occurredOn` (date-only), `renderedTextSnapshot` +
`accessibilityTextSnapshot`, optional pet/subject name snapshots (as of the
event), `localeIdentifier`, `copyDeckVersion`, `sourceEventId`, schema version,
`createdAt`. **Payloads derive from immutable event facts** (racing writers are
content-identical); rules validate type enum, schema, required fields, and
id-prefix consistency on top of create-only. The adoption moment writes in the
**same batch** as `adoptedOn`; backfill = adoption only, never guessed history.

`users/{uid}/tasks/{taskId}`
- `title`, `notes`
- `dueAt` (UTC Timestamp, nullable), `hasTime` (bool), `dueTimeZone` (IANA)
- `priority` (low | med | high)
- `listId` (nullable → Inbox)
- `repeatRule` (nullable: `{freq, interval}`)
- `completed` (bool), `completedAt` (nullable)
- `completedLocalDate`, `completedLocalMinute`, `completionTimeZone` — local context
  stamped **at completion time** (widget-drain completions included; 🆕 v0.7,
  Feature 4 — behavior is a fact about the user's day, not about the zone the device
  is in later)
- `createdAt`, `updatedAt`, `order`
- `rescheduleCount`, `originalDueAt` (v2 procrastination)
- `source` (`mochi` | `apple`) — Apple-sourced tasks live in EventKit, not Firestore;
  we keep only a lightweight reference (`ekReminderId`) + which lists are imported.

**On-device only (App Group shared storage, not Firestore):** the current mood value
+ comfort-buffer state (active pets/treats and their expiry). The widget reads these
directly; they don't need cloud sync to work.

## Apple Reminders integration (iOS-only)

So users don't maintain two todo lists. Via **EventKit**.

- **Permission:** reading existing reminders requires **full access** —
  `requestFullAccessToReminders`, with `NSRemindersFullAccessUsageDescription` in
  Info.plist (iOS 17+ auto-denies if the key is missing). Separate OS prompt from
  notifications; needs its own Mochi-voiced primer. It's a high-trust ask → keep it
  optional/skippable and also offer it in Settings.
- **v1 scope: one-way import + completion write-back.** Read selected Reminders lists,
  show them alongside native tasks, let them drive Mochi's mood; checking one off in
  Mochi marks it done in Apple Reminders. **Full two-way sync is deferred** (conflict
  resolution / dedup / delete-handling is a bug magnet).
- **Architecture:** don't copy reminders into Firestore. Treat EventKit as a live
  second source; store only a reference (`ekReminderId`, `source: apple`). The mood
  engine reads the **union** of native + Apple tasks. Each task stays in one home store.
- **List selection:** user picks *which* Reminders lists to bring in (don't gamify the
  grocery list).
- **Mood mapping:** Apple's priority (none/low/med/high) maps to ours; due date +
  priority + completion feed the engine directly.
- **Caveats:** Apple exposes no reschedule count, so the v2 procrastination signal only
  covers native tasks. Reminders completed in Apple's own app are caught on the next
  foreground/sync (via `EKEventStoreChanged`), so Mochi's reaction to those may lag —
  not instant.

## UI & navigation

**Navigation: four tabs — Home · Tasks · Journal · You** (🆕 v0.7 — was three; the
Journal is *The Personal Layer → Feature 6*).
- **Home** — Mochi (mood + tap to pet), coin pill, today's tasks, quick-add, the
  unread-letter envelope (v0.7).
- **Tasks** — Today / Upcoming / Lists / Completed.
- **Journal** — 🆕 v0.7: letters, moments timeline, "Mochi has noticed," data
  footer (counts only). See *The Personal Layer → Feature 6.*
- **You** — profile: flavors, bedtime, notification prefs, vacation mode, manage
  lists, **account & legal**. (Streaks & stats moved to the Journal in v0.7; the
  interim Letters row retired with it.)
- **Treat shop is a sheet**, not a tab — opened from the coin pill or a "Treats"
  button under Mochi. Feeding belongs next to the pet, not in a separate store.

**The mood meter must be visibly two-layer.** A solid fill for the **baseline**
(earned by tasks) plus a lighter, translucent segment stacked on top for the
**comfort buffer**, with a visual hint that it's draining. This teaches the core
mechanic. A single combined bar makes users think petting permanently fixed things.

**Naming:** call it **mood** or **comfort** — *not* "vitality" (reads as health/HP
and implies Mochi can run out, contradicting the never-dies rule). **Hide the raw
0–100 number** in the main UI; show the mood face + a qualitative label. A numeric
anxiety score is the wrong vibe.

**Flavors, not colors.** Themes are named as mochi flavors — Strawberry, Matcha, Ube,
Mango, Black Sesame — which ties the palette to the character.

## Legal & compliance

*(Not legal advice — a checklist to take to counsel. Verify against current App Store
guidelines before submission.)*

**Required by Apple:**
- **Delete account, in-app.** Guideline 5.1.1(v), effective June 30 2022: apps that
  support account creation must let users initiate deletion of the account **and its
  associated data** from within the app. Must be easy to find. **Also applies to
  auto-created "guest" accounts** — so our anonymous-auth-at-splash users need a
  deletion path too.
- **Restore Purchases** button (rejection risk without it).
- **Manage subscription** — `showManageSubscription` (iOS 15+) or link to
  `https://apps.apple.com/account/subscriptions`.
- **Paywall disclosures** — price, billing period, trial length, auto-renewal,
  cancel-anytime, + links to Terms (EULA) and Privacy Policy.
- **Privacy Policy + Terms of Use** links in-app and on the paywall.
- **Sign in with Apple** (required since we offer Google).
- Purpose strings (`NSRemindersFullAccessUsageDescription`), App Privacy nutrition
  labels, privacy manifest.
- **Sign out** + a support/contact path.

**Other:**
- **Age rating / minors.** A cute pet + subscription will attract kids. Set the rating
  deliberately, don't market to children (COPPA).
- **No mental-health claims.** Mochi gets anxious; the app does not treat anxiety.
- **GDPR/CCPA:** data export (portability) is a nice-to-have; deletion is covered above.

### Account deletion flow

**Deleting the account does NOT cancel the subscription.** The purchase belongs to the
user's *Apple ID*, not to our account record — they will keep being billed. Apple
requires we tell them so and ask them to cancel first.

1. Settings → Account → Delete account.
2. Show exactly what's destroyed (tasks, lists, coins, streak, Mochi — 🆕 v0.7: by
   *name*, including the adoption date, listed **factually and neutrally** — no guilt
   copy, no sad animation; a future return is a new adoption) — irreversible.
3. **Check RevenueCat for an active entitlement.** If active: prominent warning that
   Apple billing continues + a `showManageSubscription` button. Require acknowledgment.
4. **Reauthenticate** (Firebase requires a recent login to delete a user).
5. Double-confirm.
6. Delete Firestore subtree (Cloud Function / "Delete User Data" extension) → delete
   the RevenueCat customer → delete the Firebase Auth user → sign out.

**Can they restore afterward? Yes.** The receipt is attached to their Apple ID, so a
fresh install + **Restore Purchases** re-syncs it; RevenueCat's default transfers the
purchase to the new App User ID. Their tasks/coins/streak are gone forever, but
subscription access returns.

- **RevenueCat config trap:** keep restore behavior on the default **"Transfer to new
  App User ID."** *"Block restores"* errors when a different App User ID restores.
  *"Keep with original App User ID"* is worse on iOS — the receipt covers the whole
  Apple Account, so a new subscription would be associated with the original (deleted)
  App User ID and the customer would never gain access.
- **Warn users:** Apple tracks **trial eligibility per Apple ID**. Deleting and
  re-signing-up does **not** grant a fresh 14-day trial.

## Entitlement & subscription states

> 🆕 **v0.3 — RESOLVED.**

**Trial expiry is not an auth event.** The Firebase Auth session persists indefinitely;
only the RevenueCat *entitlement* lapses. Never log a user out to gate them — they'd just
log back in for free. **RevenueCat is the single source of truth**; the Firestore
`isSubscribed` field is an offline cache only, never computed locally.

| State | Source | Access |
|---|---|---|
| `trialing` | RC | Everything. 14 days (yearly plan only). |
| `active` | RC | Everything. |
| `billing_grace` | RC | **Everything** — see the trap below. |
| `lapsed` | ours | "Finish what you started." Indefinite. Mochi asleep. |

**The `billing_grace` trap.** A declined/expired card is *not* the same as choosing not to
renew. Apple retries billing for ~16 days and RevenueCat keeps reporting the user
**entitled**. Treat them as fully `active` with a gentle "update payment method" banner.
**Rule: if RevenueCat says entitled, they're entitled.** Misreading this locks out paying
customers over an expired Visa.

**Mochi during lapse: asleep, not sad.** "Mochi's napping until you're back." Dormant and
peaceful — mood engine paused, no stress accrual, no mood pings. Using an anxious pet as
conversion pressure is the dark pattern the whole product rejects; withholding delight is
fair, manufacturing guilt is not. The *absence* of Mochi is the pull.

**Indefinite, not timed.** Recurring-task spawning is **frozen** during lapse, so the task
list genuinely drains instead of self-replenishing into an accidental free habit-tracker.
That makes the state structurally terminal without a countdown. *(Optional belt-and-braces:
a generous ~30-day cap before a hard paywall — data still retained.)*

### Lapsed-state surface (zero ambiguity)

| Surface | Behavior when `lapsed` |
|---|---|
| Mochi | Asleep. Static sleeping pose. No mood engine, no reactions. |
| Tap-to-pet | Disabled → "Mochi's napping. Resubscribe to wake him." |
| Coin pill | Hidden. Balance **frozen & retained**, restored on resubscribe. |
| Treat shop | Inaccessible. |
| Streak | **Frozen, not broken.** Resumes on resubscribe. |
| Quick-add / new task | **Removed.** Replaced by a "Wake Mochi" CTA. |
| Existing tasks | View, **complete**, edit, snooze/reschedule, delete — all allowed. |
| Recurring tasks | Current occurrence completable. **No new occurrence spawns.** |
| Views | Today / Upcoming / Lists / Completed viewable. No new lists. |
| Notifications | **Due + overdue only, indefinitely** (Option 1, below). No mood pings / rundown / celebrations. |
| Widgets | Sleeping Mochi + next task. No mood, no tap-to-pet. |
| Themes | Locked to current. No switching. |
| Apple Reminders | Imported tasks still visible/completable. No new imports. |
| Vacation mode / bedtime | Hidden — meaningless with Mochi asleep. |
| Stats / Journal (v0.7) | Viewable, frozen. Letters + moments readable (they're theirs); nothing new composes; zero come-back copy. |
| Account & Legal | **Fully functional — non-negotiable.** Restore Purchases, Manage Subscription, Delete Account, Sign Out, Privacy, Terms, Support. Apple requires these regardless of entitlement. |
| Data | **Never deleted.** Resubscribe restores everything intact. |

The shape: *the app degrades to a plain, quiet checklist.* Everything that makes it Mochi
is asleep — which is exactly what's being sold.

**Due/overdue notifications persist forever in `lapsed` (Option 1).** The set only shrinks
(no new tasks), it costs nothing (local notifications), nobody misses a real event they set
while paying, and it's the best *useful* winback surface ("Mochi remembered your mom's
birthday").

> ⚠️ **Legal — must implement:** trial eligibility is tracked **per Apple ID**. A
> re-subscribing lapsed user gets **no second trial**. Paywall copy must query RevenueCat's
> `introEligibility` and swap *"Start free trial"* → *"Resubscribe"* for ineligible users —
> otherwise it's both an App Store rejection risk and a bait-and-switch.

## Vacation mode

> 🆕 **v0.5 — RESOLVED.** Re-entry was the last open design problem (roadmap #4).
> Locked: freeze-and-triage for one-off overdue tasks, both fixed-date and open-ended
> modes with a hard auto-expiry cap, and a **truly silent** period (no pings of any
> kind while away). Grace buffer and streak handling reuse machinery we already built.

### Intent & the promise

Vacation mode pauses **all** nudging for travel, rest, or sick days. The promise to
the user is simple and absolute: *while you're away, Mochi will not pester you, and
you will not come back to a punished pet.* This protects trust and wellbeing — the
whole reason the feature exists. Every decision below is downstream of not breaking
that promise.

The hard problem the design solves: the mood engine is deterministic and recomputes
baseline from whatever is overdue **right now**. Without intervention, a week of
one-off dated tasks ("call dentist", "pay invoice") all cross their due dates during
the trip, `R` spikes, and Mochi is instantly very sad the moment vacation ends — a
direct punishment of the exact user we told to relax. The recurrence freeze already
handles recurring tasks; **one-off dated tasks were the unguarded hole.** Re-entry is
almost entirely about defusing that pile without lying to the user forever.

### Locked decisions

- **One-off overdue tasks freeze, they don't fire.** A one-off dated task that crosses
  its due date *during* vacation generates **zero stress** and is set aside into a
  "came due while you were away" bucket. This mirrors the recurring task's silent
  missed-logging exactly — same mental model, no new invariant.
- **Both end-date models are offered.** A **fixed end date** (clean trip model, date
  picker) and an **open-ended** "until I turn it off" mode (for sick / indefinite, where
  no end date is known). Open-ended is protected by a hard **auto-expiry cap** so a
  forgotten toggle can't silently kill the app's value for weeks.
- **Truly silent for v1.** No mood pings, no reminders, no celebrations, no push of any
  kind during vacation. There is **no per-task "remind me anyway" escape hatch in v1** —
  it would erode the promise. (Deferred, not rejected; revisit only if users ask.)
- **Streaks freeze, they never break.** Breaking a streak for taking a vacation we
  sanctioned is a trust violation. The streak counter is paused on entry and resumes on
  exit, unchanged.
- **Vacation is its own instrumentation state**, excluded from the daily mood-distribution
  north-star metric so a relaxing user doesn't pollute the signal that tells us whether
  the core loop is working.
- **The app stays fully usable.** Users can still open Mochi, add tasks, and complete
  them; completions still earn coins and lift the comfort buffer normally. Vacation
  removes *pressure and pings*, not *function*.
- **The widget shows the resting pose**, an "on vacation" hint, and the end date — never a
  mood, and never the lapsed "Wake Mochi" CTA (the two calm states stay distinct). Tap-to-pet
  is off; completing a task from the widget still works. See *Widgets → State variants.*

### Lifecycle

Four phases: **enter → active → end (scheduled or capped) → re-entry.**

**Enter.** From "You" → Vacation mode. User picks fixed-date or open-ended, confirms via
a Mochi-voiced primer. On confirm: nudging suspends immediately, streak freezes, the
recurrence freeze engages (existing behavior), Mochi shifts to the resting pose.

**Active.** Mood engine runs but sees no stress: one-off due-crossings route to the
bucket; recurrence rolls are frozen; no notifications are scheduled. Baseline sits at
the content anchor. Mochi reads as *relaxed/asleep — on holiday*, visually distinct from
the lapsed "asleep (not sad)" pose. If the user opens the app, an in-app banner shows the
mode is active, the end date (or "open-ended"), and an **End vacation now** affordance. No
pushes are ever sent to prompt this — it's discovered in-app only.

**End.** Two triggers: the fixed date arrives, or open-ended hits the auto-expiry cap, or
the user ends it manually. All three route to the identical **re-entry** flow. There is no
partial or silent auto-resume — re-entry is always explicit and surfaced.

**Re-entry.** On the **first app open after the mode ends**, surface the **triage sheet**
and seed the **grace buffer** (both below). This is the moment the whole feature is built
around.

### During vacation — mechanics

- **One-off due-crossing → bucket.** Task is untouched (due date not rewritten) but
  flagged `came_due_on_vacation`. It contributes 0 to `R`. The bucket has no size cap.
- **Recurrence** stays frozen per the existing recurring-task invariant (one live
  occurrence, silent missed-logging). No change needed.
- **Mood engine** computes as normal but with an empty overdue set, so `stress = 0` and
  `baseline = A` (content). We *pin* the readable state to the resting pose regardless, so
  buffer decay or a stray imminent task can't make Mochi look anxious mid-trip.
- **Notifications**: the scheduler lays **nothing**. The morning rundown is suspended.
  Celebrations are suppressed. (Truly silent.)

### End-date model

**Fixed date.** Date picker, defaults to a sensible short trip length (Remote Config,
e.g. 7 days). Ends at local midnight of the chosen day → re-entry on next open.

**Open-ended.** No end date. Protected by two safety layers, both **in-app only** to
honor truly-silent:

1. **Long-run in-app check-in.** After `VACATION_LONGRUN_CHECKIN_DAYS` (default 14), the
   next time the user opens the app, a gentle in-app card asks "Still away? Mochi's happy
   to keep resting — or welcome back whenever." One tap to extend, one to end. No push;
   purely opportunistic on open.
2. **Hard auto-expiry cap.** At `VACATION_MAX_DAYS` (default 30) the mode ends
   automatically and routes to normal re-entry on next open. This is the backstop against
   a toggle forgotten forever. Because it funnels into the same grace-buffered triage flow,
   hitting the cap is never a punishment — worst case the user sees a triage sheet they can
   clear or dismiss in one gesture.

> Note: the cap only *ends the mode*; it does not send a notification. If the user never
> reopens the app, they simply see re-entry whenever they next do.

### Re-entry — triage sheet + grace buffer

**Triage sheet** (the pressure valve). On first open after end, a sheet lists everything
in the `came_due_on_vacation` bucket, newest-relevant first, with **bulk actions**:

- **Reschedule** — bulk "push all to this week" or per-task date, for things that still
  matter.
- **Complete** — for things done during the trip / no longer needed as reminders.
- **Dismiss** — drop from the list without completing (the "never mind" pile).

Resolving the pile in one gesture is the entire point: the user clears a week of drift in
seconds instead of task-by-task. The sheet is **skippable** ("Later") — which is exactly
what the grace buffer is for.

**Grace buffer** (reuses the comfort-buffer subsystem — device-local, decaying). On
re-entry, seed a lift sized to put Mochi at ~content (`VACATION_GRACE_WAKE`, default = `A`
= 58) **regardless of the true pile**, decaying to zero over `VACATION_GRACE_DECAY_H`
(default 24h).

- If they clear the pile via triage, true baseline rises to meet or exceed the buffer and
  they never perceive a dip — Mochi just woke up content and got happier.
- If they dismiss triage and do nothing, Mochi drifts *down* from content to the real
  earned mood over ~24h. Gentle, honest, never an ambush, and never a permanent lie.

This is precisely the "wake near content, drift down" behavior — pinned to existing
machinery rather than a new subsystem.

### Constants (Remote Config — all tunable)

| Constant | Default | Purpose |
|---|---|---|
| `VACATION_DEFAULT_DAYS` | 7 | Fixed-mode date-picker default |
| `VACATION_GRACE_WAKE` | 58 (= `A`) | Re-entry wake target (content anchor) |
| `VACATION_GRACE_DECAY_H` | 24 | Grace-buffer decay window on re-entry |
| `VACATION_LONGRUN_CHECKIN_DAYS` | 14 | Open-ended in-app "still away?" threshold |
| `VACATION_MAX_DAYS` | 30 | Open-ended hard auto-expiry cap |

Bucket size: uncapped. Streak: frozen (no constant).

### UI specifications

Overarching rule: **vacation is a mode, not a screen.** It changes the state of Mochi, the
home surface, and the scheduler — so the UI's job is to make the mode *legible* at a glance
(am I on vacation? until when?) and make entering/exiting *low-friction and reassuring*.
Everything below is Mochi-voiced and cozy, never clinical.

**1. Entry point — "You" → Vacation mode row.** A single row with a Mochi-holiday glyph.
Off state: "Vacation mode — pause all nudging." Tapping opens the entry sheet.

**2. Entry sheet.** A bottom sheet, not a full screen (this is a light action). Mochi in the
resting/holiday pose at the top, animating once. Primer copy in Mochi's voice states the
promise plainly — "I'll rest while you're away. Nothing overdue, no pings, and you won't
come back to a sad me." A segmented control: **Set an end date** | **Until I turn it off.**
Fixed shows an inline date picker defaulting to `VACATION_DEFAULT_DAYS` out; open-ended shows
a one-line reassurance that Mochi will quietly check in after a couple of weeks and won't
rest forever. Primary button **Start vacation**, secondary **Cancel**.

**3. Active-vacation home.** The home surface, restyled to read *paused*. Mochi in the
holiday pose (hammock / sunglasses — ties to the pose-set commission, roadmap #6; until art
lands, reuse the calm sleeping pose with a holiday accent). A persistent soft **banner**:
"On vacation 🌴 — back **Sat Jul 25**" (or "back whenever you're ready" for open-ended), with
a subtle **End now** text button. The task list stays present and usable but visually
de-emphasized (no overdue-red, no stress coloring — everything neutral). No mood-state chrome
(no anxious faces, no climbing counters).

**4. Open-ended long-run check-in card.** After 14 days, on open, an inline card above the
list (not a modal): "Still away? I'm happy to keep resting 🌙" with **Keep resting** /
**Welcome me back**. Dismissible; reappears at a Remote-Config interval, not every open.

**5. Re-entry triage sheet.** On first open after the mode ends. Header: Mochi waking up,
mid-stretch, content pose. Copy: "Welcome back! Here's what came due while you were away —
let's sort it fast." The bucket list, each row with quick per-item actions and a sticky bulk
bar at the bottom: **Reschedule all to this week · Complete all · Dismiss all.** Skippable
via **Later**, which drops to the normal home with the grace buffer already holding Mochi at
content. If the bucket is empty (user cleared everything during the trip, or had no dated
one-offs), skip the sheet entirely and go straight to a small "Welcome back!" celebration —
don't show an empty triage sheet.

**6. Post-triage home.** Normal home. If the pile was cleared, Mochi is content→happy and the
grace buffer is redundant (fine). If skipped, Mochi sits at content and drifts to true mood
over 24h — no explicit UI for the drift; it's just Mochi being Mochi.

**Accessibility.** The holiday pose needs a distinct **VoiceOver label** ("Mochi is resting —
vacation mode on") separate from the lapsed "asleep" label, so the two calm states aren't
conflated. The banner's end date must be readable text, not conveyed by color alone.

### Flow examples

**Flow A — Fixed-date trip, user triages on return (happy path).** Enter → pick "back in 7
days" → Mochi rests, banner shows the date → user travels, opens the app twice mid-trip and
sees only the calm paused home → day 7 passes → first open shows triage sheet with 5 buckets
→ user taps "Reschedule all to this week" → Mochi wakes content and lifts as the rescheduled
tasks are on-time → done.

**Flow B — Open-ended sick leave, user ignores triage.** Enter → "until I turn it off" → Mochi
rests → day 14, on open, gentle in-app check-in → user taps "Keep resting" → recovers, on day
18 opens app and taps **End now** on the banner → triage sheet appears → user taps **Later** →
grace buffer holds Mochi at content → over 24h Mochi drifts to true mood as the still-unresolved
pile reasserts → user handles tasks organically over the day.

**Flow C — Forgotten open-ended toggle (safety net).** Enter open-ended → user forgets → day
30, auto-expiry cap ends the mode silently → user opens the app a week later → sees the standard
re-entry triage sheet (grace-buffered), not a very-sad Mochi → clears or dismisses → no trust
damage despite a month of neglect.

**Flow D — Empty bucket (no dated one-offs).** Enter → trip → return → bucket is empty → no
triage sheet → straight to "Welcome back!" celebration → normal home.

### Use cases

- **Weekend getaway.** Fixed 3 days. Expects zero friction and a warm welcome back. Flow A.
- **Two-week holiday with real obligations queued.** Fixed 14 days; several bills/appointments
  came due. The triage sheet's bulk-reschedule is the hero interaction. Flow A.
- **Sick, indefinite.** Open-ended; may last days or weeks. Needs the check-in + cap so the app
  neither nags nor silently dies. Flow B / C.
- **Burnout / mental-health rest.** Open-ended; the *truly silent* promise is the point — no
  escape-hatch pings undermining it. Flow B.
- **Set it and forgot it.** The cap is the safety net; re-entry must never punish. Flow C.

### Edge-case matrix

| # | Situation | Behavior |
|---|---|---|
| 1 | One-off task crosses due date during vacation | → bucket, 0 stress, due date unchanged |
| 2 | Recurring task due during vacation | Frozen per existing recurrence invariant (no change) |
| 3 | User completes a task during vacation | Works normally; earns coins; lifts buffer; no pressure |
| 4 | User adds a task during vacation due before end | Normal add; if it crosses due before end, → bucket |
| 5 | Imminent/overdue task exists at moment of entry | Its stress is cleared on entry; routed to bucket on end |
| 6 | Buffer decays to zero mid-vacation | Mochi still reads resting (state is pinned), not sad |
| 7 | Fixed end date arrives while app is closed | Mode ends; re-entry surfaces on next open |
| 8 | Open-ended reaches `VACATION_MAX_DAYS` while app closed | Auto-expiry ends mode; re-entry on next open |
| 9 | User opens app after end but before triaging | Triage sheet shown; grace buffer already seeded |
| 10 | User skips triage ("Later") | Grace buffer holds content; drifts to true mood over 24h |
| 11 | User clears entire pile in triage | True baseline meets/exceeds buffer; no perceived dip |
| 12 | Bucket empty on re-entry | Skip triage; show "Welcome back" celebration |
| 13 | Streak active at entry | Frozen; resumes unchanged on exit |
| 14 | User ends vacation manually mid-trip | Immediate re-entry flow (triage + grace) |
| 15 | User re-enters vacation immediately after ending | Allowed; new bucket starts empty |
| 16 | Multi-device: vacation toggled on phone | Mode is synced state (entitlement-like); buffer stays device-local per existing rule |
| 17 | Lapsed entitlement during vacation | Entitlement states take precedence; vacation is moot while lapsed (Mochi asleep for lapse, not vacation) |
| 18 | Quiet hours × vacation | Moot — nothing is scheduled during vacation anyway |
| 19 | Long open-ended: user taps "Keep resting" at check-in | Extends; check-in re-arms at interval; cap still applies |
| 20 | Notifications permission denied, then vacation | No change; vacation was silent regardless |

### Instrumentation

- Log a distinct `vacation` mood/session state; **exclude it from the daily mood-state
  distribution** north-star metric.
- Log entry (fixed vs open-ended, chosen length), exit trigger (scheduled / manual /
  auto-expiry-cap), bucket size at re-entry, and triage action taken (reschedule-all /
  complete-all / dismiss-all / per-item / skipped).
- Never log task titles (consistent with the global privacy rule).
- Alert-only tripwire if auto-expiry-cap fires disproportionately often (signals people
  forgetting the toggle → maybe shorten the check-in interval).

### Deferred (not in v1)

- Per-task "remind me even on vacation" escape hatch.
- Push-based (rather than in-app) long-run check-in.
- Smart pre-trip suggestion ("looks like you have nothing due this week — vacation?").

## Onboarding

Guiding rule: **let users meet Mochi and feel the hook before asking for an
account or payment.** Every extra screen loses people — cut any step that doesn't
earn its keep.

1. **Splash** — branded, Mochi animating. Firebase initializes; **create an
   anonymous auth session here** so onboarding choices save immediately. Returning
   users skip straight to home.
2. **Meet Mochi** — 2–3 delightful screens introducing him and the core idea, with
   mood animations. The emotional hook. 🆕 v0.7: ends on the **naming beat** —
   "What will you call them?", skippable, default "Mochi"; the chosen name is used on
   the very next screen. See *The Personal Layer → Feature 1.*
3. **Add your first task** — the activation moment and biggest retention lever.
   Guide them to add one reminder, then show Mochi light up. Skippable, but this is
   where the loop clicks with their own data (and it keeps the home screen from being
   empty on first open).
4. **Pick a theme** — fun, low-friction, personalizes Mochi's world.
5. **Set bedtime** — enables sleep + the morning rundown from day one.
6. **Notification permission** — critical; the whole app depends on it. This is a
   **primer** you control (Mochi's voice, your own buttons) — you only fire the real
   iOS prompt if they say yes, because you get **exactly one shot** at the system
   dialog (a "Don't Allow" is permanent, Settings-only). Placed late, after the value
   is obvious. Graceful fallback if denied (badge-only, or start with *provisional* auth).
7. **Apple Reminders (optional, skippable)** — for people who already use Reminders,
   offer to bring them in so Mochi tracks everything in one place. Mochi-voiced primer
   → EventKit full-access prompt. **Skippable**, and also available later in Settings
   (don't stack two mandatory permission walls). iOS-only.
8. **Continue with Apple / Google** — now they're invested. Firebase Auth; **link**
   the credential to the anonymous account (`linkWithCredential`) so nothing is lost.
9. **Paywall** — with a free trial. Placed after the value moment, where conversion
   actually happens.
10. **Home** — plus a nudge to add the home-screen widget (clunky on iOS; guide it —
    it's a top retention driver).

### Exploring: the waking-Mochi adoption beat

> 🆕 **v0.8 — EXPLORING, not specced.** An idea for replacing the passive "Meet Mochi"
> screens (step 2) with an interactive one for new accounts. Captured here so it isn't
> lost; needs a design pass and a comp before it is a decision.

**The shape.** The splash still exists and still does its job (branding, Firebase init,
the anonymous auth session). On a **new account only**, the flow that follows is not a
carousel you swipe through but a creature you wake up:

1. **Asleep.** Mochi is curled up and sleeping. Minimal chrome, a soft prompt to tap.
2. **Tap → groggy.** He stirs. Eyes half open, a stretch, still mostly out of it.
3. **Tap → awake.** He's up, looking at you, curious.
4. **Tap → adopted.** He lights up happy, and *that* is the naming beat: "What will you
   call them?" The adoption is something the user performed, not a form field they
   filled in.
5. Continue into the existing flow (first task → theme → bedtime → notifications → …).

**Why it's worth exploring.** The naming beat (Feature 1) currently arrives as the tail
of a passive intro. Three taps of escalating response make the same moment
*participatory*: the user woke him, so naming him reads as adoption rather than data
entry. It also teaches the tap-to-pet gesture before Home ever asks for it, and it puts
the mood system on screen as a thing that responds to you rather than a thing described
to you.

**What has to be answered before this becomes a spec:**

- **Returning users skip it entirely.** The whole sequence is first-run-only, gated the
  same way step 1 already gates returning users. An interrupted onboarding must not
  re-run the wake on the next launch and re-ask for adoption; the
  `PetIdentityStore` migration backstop at `enteredHome` already covers the
  interrupted-naming case and needs to stay authoritative.
- **`adoptedOn` is write-once, enforced by Firestore rules** (Feature 1). The stamp
  fires at the naming beat regardless of which path reaches it, so the wake sequence
  must not introduce a second stamping site.
- **Art dependency.** Asleep and content poses exist in the scripted idle set; groggy
  and the adoption-happy beat do not. This lands on the pose list in
  `waiting-on-assets.md` and may want the Rive rig rather than scripted canvases.
- **Skippability.** Every other onboarding step is skippable by design. Three mandatory
  taps is a hard gate on the first screen a user ever sees. Either the taps auto-advance
  on a timer if untouched, or there is a skip that jumps straight to the naming beat.
- **Reduce Motion and VoiceOver.** The sequence is entirely animation-carried. It needs
  a static equivalent that still reaches the naming beat, and each state needs a label
  distinct from the existing sleeping-pose label.
- **Does the tap escalate mood, or is it scripted?** Scripted is almost certainly right
  (the real mood engine has no data yet on a fresh account), but the seam between "this
  scripted sequence" and "the live mood system" should be deliberate.

## Widgets

> 🆕 **v0.6 — RESOLVED.** Surfaces, interactions, the App Group data contract, the
> forecast-driven timeline, iOS 26 rendering, and every state variant are locked. Ready to
> scaffold. Product-level "all included" framing lives above under *Themes, widgets, features*;
> this is the engineering spec.

**Target structure.** A **WidgetKit extension** plus a **shared framework** (the deterministic
mood engine + App Group accessors) linked by *both* the app and the widget. The widget renders
**static image assets only** and **never loads Rive** (widget-extension memory ceiling — roadmap
#8). Everything it shows comes from **App Group shared storage** — no Firestore, no EventKit, no
network at render time.

### Surfaces

Home screen:
- **Small** — Mochi's face at current mood.
- **Medium** — Mochi + next task.
- **Large** — Mochi + next 2–3 tasks + coin balance. *(Fast-follow; ship small + medium first.)*

Lock screen (all rendered **monochrome/tinted — no color**):
- **Circular** — tinted Mochi glyph / mood gauge. The glanceable "mood ring."
- **Rectangular** — tinted mini-Mochi + next task title/time.
- **Inline** — one line, next task only. No Mochi.

**Out of v1:** StandBy, Control Center controls, Watch complication, live animation, sound.
**Explicitly not Live Activities / Dynamic Island** — wrong tool for ambient mood (they're
event-scoped and temporary); reserved for a possible future Focus/Pomodoro session.

### Interactions (App Intents, iOS 17+)

- **Pet** *(home screen only)* — bumps the **device-local** comfort buffer, recomputes, writes
  the App Group snapshot, reloads the timeline. Stays entirely inside the App Group; no sync.
- **Complete a task** *(home screen)* — **in v1.** Unlike Pet, this must write **durably to the
  source of truth** (Firestore, or EventKit for Apple-sourced tasks), not just the App Group;
  Firestore's offline queue absorbs it if offline. Removes stress at the source, awards the coin,
  re-lays the schedule, reloads the widget. Heavier than Pet — plan the write + rollback path.
- Interaction-triggered reloads and foreground reloads are **free** against the ~40–70/day
  timeline budget.

### Timeline = the notification forecast (not optional)

The widget timeline **is** the mood-ping forecast, reused verbatim — one engine parameterized by
time, the invariant already committed to in *Notifications → Mood pings*. We emit **future-dated
timeline entries** straight from `moodForecast`, so the widget visibly moves through moods on its
own as tasks age while the app is closed, with **no wasted reloads**. Same
monotonic-until-saturation curve, ≤3 band crossings, horizon **capped at entitlement expiry**,
baking in recurrence roll-forward + vacation auto-expiry. A widget refresh and a mood ping are
the *same pre-evaluation of the same curve*, so they can never contradict each other or
`mood(now)` on next open.

### App Group data contract

The app **owns all writes**; the widget **only reads**. The mood value + comfort-buffer state
already live here; **theme, the next-task projection, and the flags below must be mirrored from
Firestore into the App Group by the app** — that mirroring is the piece that wasn't previously
written down.

```
MochiWidgetState (App Group, versioned):
  schemaVersion
  displayState:   active | lapsed | vacation        // drives pose + chrome
  theme:          id                                // selects the pose asset set
  moodForecast:   [(date, moodState)]               // == notification forecast output
  hideTaskNames:  bool                              // lock-screen privacy toggle
  mochiName:      string                            // 🆕 v0.7 — falls back to "Mochi" if absent
  nextTasks:      [{ id, title, due, completable }] // top 1–3 (morning-rundown ranking)
  vacationEnd:    date?                              // for the "on vacation" hint
  lastComputed:   timestamp
```

### iOS 26 rendering

On a themed ("Liquid Glass") home screen, WidgetKit **desaturates/tints widget content** unless
you opt out. Because **mood is partly carried by color** (green content-Mochi vs. grey anxious
Mochi), mark the Mochi image **`fullColor`** (`widgetAccentedRenderingMode`) so mood always
reads; let the surrounding chrome (task text, coin count) take the system's accented treatment.
The **lock screen is monochrome regardless** — see the pose-legibility constraint below.

### State variants (`displayState`)

| State | Pose | Task info | Tap-to-pet | Complete | Chrome |
|---|---|---|---|---|---|
| **active** | current mood | next 1–3 | ✅ *(home)* | ✅ *(home)* | mood-colored |
| **lapsed** | **asleep** | next task | ❌ | ✅ *(existing tasks stay completable)* | **"Wake Mochi"** resubscribe CTA |
| **vacation** | **resting** *(holiday pose)* | next task | ❌ | ✅ | **"On vacation"** + end date; **no** Wake CTA |

**vacation ≠ lapsed on purpose.** They reuse *different* existing poses — vacation the
**resting/holiday** pose (matching the in-app pose + its VoiceOver label "Mochi is resting"),
lapsed the **asleep** pose — so the two calm states are never conflated (a locked in-app
decision). **No mood is shown in either.**

### Asset set (blocks shipping, not scaffolding)

Static exports per theme: **6 mood poses + asleep (lapsed) + resting (vacation)** — all reused
from in-app poses, **no widget-only art**. **Lock-screen legibility constraint (animator brief,
roadmap #6):** every pose must read as a **monochrome silhouette** — anxious-vs-content cannot
rely on hue, because the lock screen flattens all color.

## The Personal Layer

> 🆕 **v0.7.** Six features, one shared job: convert data the app already collects into
> evidence that Mochi *knows the user*. **All six features are RESOLVED** — the
> layer's design is complete; implementation proceeds in the pinned build order.
> Tracked as roadmap #10.

### Why this exists (product rationale)

Nobody subscribes to a todo app for its analytics — productivity stats are a commodity
and a retention feature at best. The purchase decision in this category is emotional:
*"I have a relationship with this creature and I don't want to lose it"* (the
Finch precedent — a mechanically simpler todo app that sells on the strength of the
bond alone). The Personal Layer is how that bond compounds: the pet stops being a mood
meter and becomes a companion with a name, a history, and observations about *you*.

**Governing rule (holds every decision in this section): charts measure, companions
notice.** The same datum can be rendered as either — "72% on-time" is measurement;
"you do your best work on Tuesday mornings, Mochi keeps notes" is noticing. Anything
in this layer that reads as measurement gets rewritten or cut. Corollaries, inherited
from locked decisions elsewhere: no guilt ledger (negative history is never surfaced),
insight framings are always neutral-to-positive, and everything computes **locally and
deterministically** (same doctrine as the mood engine — pure functions over synced
data, testable, no server).

### The six features

| # | Feature | Status | One-liner |
|---|---|---|---|
| 1 | Name your Mochi + adoption date | ✅ **Resolved (v0.7)** | Ownership language; the foundation the rest builds on |
| 2 | Anniversaries & memory callbacks | ✅ **Resolved (v0.7)** | Sparse milestones + mood-gated positive callbacks, entirely on existing rails |
| 3 | Weekly letter from Mochi | ✅ **Resolved (v0.7)** | The flagship: an immutable Sunday recap in Mochi's voice; compose-once, archive-bound, shareable |
| 4 | Mochi's observations (insight engine) | ✅ **Resolved (v0.7)** | Pure engine turning completion stats into things Mochi *noticed*; also the distribution source for Feature 5 |
| 5 | Suggested times | ✅ **Resolved (v0.7)** | The insight that acts: editor-only chips from real behavior; the layer's designated validator |
| 6 | Journal tab | ✅ **Resolved (v0.7)** | The container; fourth tab; zero new engines or tuning surface — purely curatorial |

**Build order: 1 → 4 → 3 → 2 → 5 → 6.** Rationale: naming lifts every existing copy
surface for days of work; the observation engine (4) is pure functions + tests with no
UI and is the dependency for 3 and 5; the letter (3) is the flagship and ships with a
small beat library that grows; anniversaries (2) ride existing rundown/celebration
rails; suggested times (5) doubles as the validation instrument for the whole layer;
the Journal tab (6) only earns a tab once 1–4 give it content — shipping it first
would just repaint the stats page that already exists.

---

### Feature 1 — Name your Mochi + adoption date

> 🆕 **v0.7 — RESOLVED** *(revised same-day after review: adoption date reworked to a
> date-only `adoptedOn` stamped at the naming beat, one-time persisted migration,
> server-side write-once enforcement, rename propagation centralized as
> `PetIdentityDidChange` incl. action-label re-registration, rename allowed while
> lapsed, precise Unicode sanitization, compact-layout fallbacks, required test
> matrix).* The cheapest feature in the layer and the highest ROI. Ownership language
> is the foundation every other Personal Layer feature builds on.

#### Intent

A named pet is *theirs*. Every notification, rundown, and banner that says the chosen
name reads as their pet speaking, not an app template — which sharpens the exact
emotional mechanism the product sells. The adoption date gives the relationship a
beginning, which Feature 2 (anniversaries) and Feature 3 (letters) consume. For a
lapsed user, a named Mochi still asleep in the app is the winback lever the
"data never deleted" decision already paid for.

#### Locked decisions

- **Default name is "Mochi."** Naming is offered, never required. Skip = "Mochi",
  renamable later. The brand name doubles as the default pet name by design.
- **The name is the pet's, not the app's.** It replaces "Mochi" in all
  *pet-referential* copy (the pet speaking, being spoken about, or being acted on).
  It never replaces the brand: app name, App Store presence, paywall product naming,
  and legal surfaces always say "Mochi." **Implementation requires an audit, not a
  search-and-replace:** every hard-coded "Mochi" in the codebase is classified as
  *brand usage* (stays literal) or *pet-reference usage* (routes through the one
  templating helper). A global replace would rename the brand.
- **Promise copy may never embed the pet name.** Reminders name the *task* (their
  locked job) and stay pet-name-free — so a rename never requires touching a promise.
  Promises are sacred and never wiped; this rule keeps that invariant intact **by
  construction** rather than by migration. Mood pings and rundowns may use the name
  freely because re-lay already rewrites them.
- **`adoptedOn` is date-only and stamped when the naming beat completes** — the
  literal "day you met," not the account-creation instant (`createdAt` remains a
  separate fact: the exact account-creation timestamp, never displayed as the adoption
  date). Date-only means a timezone change can never shift the displayed date.
  Write-once: it survives lapse, vacation, and rename; only account deletion destroys
  it (a post-deletion return is a *new* adoption — consistent with "tasks/coins/streak
  are gone forever").
- **Write-once is enforced server-side.** Firestore security rules reject any update
  or delete of `adoptedOn` once present. Client code preserving the invariant is a
  courtesy; the rules are the guarantee.
- **Rename is available in every entitlement state, including `lapsed`.** Fixing a
  typo wakes nothing, unlocks nothing paid, and touches no scheduler while nothing is
  scheduled. Withholding a text field as resubscribe pressure is exactly the kind of
  manipulation the product rejects. *(Revised: the first draft hid the rename row
  while lapsed.)*
- **Every rename entry point routes through one `PetIdentityDidChange` pipeline**
  (below), so no surface can be forgotten as new ones are added.
- **The name is never logged.** Same rule as task titles: user content stays out of
  analytics and Crashlytics. Instrumentation records *that* a pet was named or renamed,
  never *what*.
- **Any printable characters are allowed.** It's their pet. Sanitization handles
  safety and length (below); we do not police taste. (Emoji in a name is the user's
  choice; the no-emoji rule governs *our* copy, not theirs.)
- **Account deletion stays neutral.** The deletion screen lists the pet's name and
  adoption date factually among the destroyed data — required disclosure — with no
  guilt-heavy relationship copy and no sad animation. Losing a named pet is already
  weighty; dramatizing it at the deletion gate would be manipulation.

#### Data model

`users/{uid}` gains:

- `mochiName` (string, default `"Mochi"`) — sanitized before every write.
- `adoptedOn` (date-only string, `YYYY-MM-DD`) — the calendar date in the user's
  current timezone at the moment the naming beat completes. **Backstop:** if
  onboarding is interrupted after profile creation but before the naming beat, stamp
  it on first arrival at Home — the field always exists once onboarding is behind the
  user.

Both sync via Firestore like any profile field. The comfort-buffer's device-local rule
does **not** apply here — the name must agree across devices.

**Migration (one-time, persisted — not decoder-fallbacks-forever).** On first run of a
build with this feature, for existing profiles: missing `mochiName` → write `"Mochi"`;
missing `adoptedOn` → backfill from `createdAt` converted to a calendar date in the
device's current timezone, and **persist the backfill**. Decoder fallbacks (absent
field reads as "Mochi") exist only as a transient safety net for the pre-migration
window — same doctrine as the removed `level` pref: stale shapes are handled once,
then the persisted value is the truth.

**Sanitization (at every persistence boundary, same doctrine as bedtime windows):**

- **Remove:** line breaks, C0/C1 control characters, and disruptive bidirectional
  controls (directional overrides / embeddings / isolates, U+202A–U+202E and
  U+2066–U+2069).
- **Preserve:** everything a legitimate name needs — combining marks, CJK, RTL
  scripts, and full emoji sequences. **Never strip ZWJ (U+200D) or variation
  selectors:** a stripped joiner corrupts a joined emoji into its component parts.
- Trim leading/trailing whitespace; collapse internal runs to single spaces.
- Cap at **16 grapheme clusters**, cutting only on grapheme boundaries.
- **Classification:** a valid-but-overlong string → sanitize and cap. A missing
  field, wrong-type value, or string that is empty *after* sanitization → `"Mochi"`.
- **IME safety:** the live field cap counts *committed* graphemes and never interferes
  with marked (in-composition) text — CJK composition completes first, then the cap
  applies on commit.

#### Naming — onboarding

Extends the *Meet Mochi* step (onboarding step 2) with a closing beat — not a new
screen inserted elsewhere, because naming is part of *meeting*:

- The last Meet Mochi screen ends on the naming card: Mochi front and center,
  prompt in the established voice, e.g. **"They need a name. What will you call
  them?"** — text field with placeholder "Mochi", live 16-grapheme cap.
- Primary button confirms; a quiet **"Mochi is perfect"** secondary keeps the default.
  Both advance; there is no wrong exit and no validation error state the user can see
  (sanitization is silent).
- Completing the beat (either button) stamps `adoptedOn`.
- No coin, no celebration — naming is a quiet, warm moment, not a reward event.
- The chosen name is used *immediately* on the very next onboarding screen ("Add your
  first task" copy says the name) — instant proof the choice took.

#### Rename — the You tab

- A **"Your Mochi"** row group in "You" (sits naturally above streaks & stats):
  shows the current name and **"Met on {adoptedOn}"** as a read-only line, rendered
  verbatim from the date-only value (no timezone math — it can never shift). Tapping
  the name opens a small rename sheet (same field, same rules).
- Available in **every** state: active, vacation (the app stays fully usable; the
  scheduler lays nothing anyway), and lapsed (a pure text fix — see locked decisions).
- A rename whose sanitized value equals the current name is a **no-op**: no write, no
  propagation, no instrumentation event.
- A real change fires `PetIdentityDidChange`.

#### `PetIdentityDidChange` — the propagation pipeline

One centralized flow; every rename entry point (the You tab today, anything future)
goes through it, in order:

1. **Sanitize + persist** the profile write (the whole pipeline is skipped if the
   sanitized value is unchanged).
2. **Re-register notification categories/actions** whose labels embed the name —
   "Pet {name}", "{name}, shh · {N}h" — *before* any re-lay, so newly laid
   notifications reference matching action labels.
3. **Notification re-lay** — mood pings + rundowns rewritten with the new name;
   promises untouched (they contain no name, by the locked rule). Rename joins the
   re-lay trigger list.
4. **Widget mirror write + reload** (`mochiName` in `MochiWidgetState`).
5. **Live UI refresh** via the observed profile (Home, treat shop, banners,
   accessibility labels).

#### Name-usage map

One templating helper (full-sentence String Catalog keys with a `%@` argument — never
concatenation, per the localization rule). Copy guidance: **prefer sentence shapes that
take the bare name** ("Nori is missing you") over possessives where an equally natural
line exists — possessive morphology localizes badly.

| Surface | Uses the name? | Notes |
|---|---|---|
| Mood pings | ✅ | "Nori is missing you." Stays vague about tasks per locked voice rules |
| Morning rundown | ✅ | Signature/voice line; task names unchanged |
| Celebrations | ✅ | **In-app** banners via `CelebrationCenter` — no celebration push exists (v0.6.1 locked decision). The requirement extends to any future celebration push if that path ever ships |
| **Promises (reminders)** | **❌ — never** | Locked above; renames can never require touching one |
| Notification action labels | ✅ *(with fallback)* | "Pet Nori", "Nori, shh · 24h" — subject to the compact-surface budget below; re-registered by `PetIdentityDidChange` |
| Onboarding, primers | ✅ | From the naming beat onward |
| Treat shop, pet/tap copy | ✅ | "Give Nori a dango" |
| Vacation surfaces | ✅ | Banner, entry sheet, check-in card, triage header |
| Lapsed surfaces | ✅ | "Nori is napping. Resubscribe to wake them." The Wake CTA reads "Wake Nori" — honest labeling, not a comeback nudge, so it stays inside the winback doctrine |
| Widget (all families) | ✅ | Chrome where text fits + **VoiceOver labels** ("Nori is resting — vacation mode on") |
| App name, paywall product, App Store, legal | ❌ | Brand is "Mochi", always |
| Analytics / logs | ❌ — never | Locked above |

**"Hide task names on lock screen" does not affect the pet name.** That toggle governs
*task content*; mood pings are already task-nameless and carry the pet name by design.
A user who wants the pet name off the lock screen has the per-category mood-ping
toggle.

#### Compact surfaces — truncation & fallback

Sixteen graphemes can still overflow small surfaces (wide CJK and emoji-sequence
graphemes render far wider than 16 Latin characters). Per-surface rules; **wherever
the platform allows a separate accessibility label, VoiceOver always gets the full
name.**

| Surface | Rule |
|---|---|
| In-app buttons / CTAs | Name included when it fits the layout; otherwise verb-only visual label ("Wake") with the full name in `accessibilityLabel` ("Wake Nori") |
| Widget chrome | Standard end-truncation with ellipsis; the VoiceOver label carries the full name |
| Notification **action titles** | `UNNotificationAction` has a single title (no separate a11y label) — include the name only when the composed title stays within a compact budget (verb + ~12 characters); otherwise verb-only ("Pet", "Shh · 24h") |
| Notification body copy | Full name always — bodies wrap; no fallback needed |
| Lock-screen inline widget | Never shows the name (task-only surface, unchanged) |

#### Widget contract

`MochiWidgetState` gains `mochiName` (schemaVersion bump; the widget falls back to
"Mochi" on a stale/absent field, so app-first update order is safe). Mirrored on every
write like theme — the mirror already runs after every re-lay, and rename triggers one.

#### Edge-case matrix

| # | Situation | Behavior |
|---|---|---|
| 1 | User skips naming at onboarding | Name = "Mochi"; renamable later; no nagging to name. `adoptedOn` still stamped at the beat |
| 2 | Onboarding interrupted before the naming beat | Backstop stamps `adoptedOn` on first arrival at Home; naming stays available in "You" |
| 3 | Empty / whitespace-only input | Silently becomes "Mochi"; no error state |
| 4 | Input at the 16-grapheme cap | Field stops accepting committed graphemes; no truncation-on-save surprises |
| 5 | CJK input near the cap | Marked (in-composition) text is never blocked; the cap applies on commit |
| 6 | Emoji sequences (ZWJ, skin tones, flags) | Preserved intact — joiners and variation selectors are never stripped; each sequence counts as one grapheme |
| 7 | RTL / bidi names | Stored verbatim minus directional-control characters; must render correctly inside LTR copy sentences |
| 8 | User names the pet "Mochi" | Fine; identical to default (`pet_named` logs *default* — the metric keys off the value, not the button) |
| 9 | Rename to the same sanitized value | No-op: no write, no propagation, no `pet_renamed` event |
| 10 | Rename with pending mood pings scheduled | `PetIdentityDidChange`: action labels re-registered, `mood-*`/rundowns rewritten; promises untouched (contain no name, by rule) |
| 11 | Mood ping fires with the old name (rename on another device, no foreground yet) | Accepted staleness — same class as external-completion staleness; caught on next foreground via the normal profile-change → re-lay path |
| 12 | Rename during vacation | Allowed; nothing is scheduled anyway; mirror updates so the widget banner shows the new name |
| 13 | Rename while lapsed | **Allowed** — pure text fix; wakes nothing, unlocks nothing, schedules nothing (promises carry no name) |
| 14 | Legacy profile missing the new fields | One-time migration writes `mochiName = "Mochi"` and backfills `adoptedOn` from `createdAt`, persisted; decoder fallback covers only the pre-migration window |
| 15 | `linkWithCredential` collision, both accounts named | The *existing* account's name and `adoptedOn` win — real history always wins |
| 16 | Collision: existing account unnamed (or default) + anon session custom-named | The custom name is kept — an unnamed account has no *naming* history to win with. `adoptedOn` still comes from the existing account (backfilled if needed): the relationship started then, whatever the pet is called now |
| 17 | Apple/Google sign-in supplies the user's real name | **Never** used as a pet-name default or suggestion |
| 18 | Account deletion → later return | Name + `adoptedOn` destroyed with the subtree; the return is a new adoption with a fresh date. Deletion screen lists the name + adoption date **factually, neutrally** (locked decision) |
| 19 | Attempted `adoptedOn` mutation (any client) | Rejected by Firestore security rules — server-side, not client courtesy |
| 20 | Malformed value read from Firestore | Valid-but-overlong string → sanitize + cap. Wrong type / empty after sanitization → "Mochi". Never broken copy |
| 21 | Timezone change | `adoptedOn` is date-only and rendered verbatim — the displayed date never shifts |
| 22 | Maximum-width name on compact surfaces | Per-surface fallback table above; VoiceOver keeps the full name where the platform allows |
| 23 | Localization | The name is user content: inserted via `%@`, never localized, never transformed (no casing changes) |

#### Instrumentation

- `pet_named` at onboarding: one boolean dimension — **custom = sanitized name ≠
  "Mochi"**, regardless of which button confirmed it. Never the string.
- `pet_renamed`: fires **only when the sanitized value actually changes** (no-op
  renames don't write, don't propagate, don't log). Count only, never the string.
- Nothing else — this feature's real metric shows up indirectly, in whether
  name-bearing surfaces outperform (Feature 5's acceptance instrumentation is the
  layer's designated validation instrument).

#### Test coverage (required)

- **Sanitization table-drive:** custom / default / empty / whitespace-only /
  emoji-sequence (ZWJ, skin tone, flag) / combining marks / CJK / RTL + bidi controls /
  overlong-valid / wrong-type — each asserting the classified outcome (cap vs.
  fallback).
- **IME:** composition near the cap never blocks marked text; cap applies on commit.
- **Interrupted onboarding:** naming beat skipped mid-flow → backstop stamps
  `adoptedOn` at Home.
- **Migration:** legacy profile gains both fields exactly once; second run is a no-op;
  pre-migration decode falls back without writing.
- **Write-once:** `adoptedOn` mutation rejected by security rules (rules-emulator
  test).
- **`PetIdentityDidChange`:** action labels re-registered before re-lay; mood pings +
  rundowns rewritten; **promises byte-identical before/after**; mirror written; widget
  reloaded; accessibility labels updated.
- **No-op rename:** no write, no re-lay, no event.
- **Cross-device staleness:** rename elsewhere → foreground catch-up path re-lays.
- **Credential collisions:** both-named and unnamed-legacy + custom-anon variants.
- **Timezone change:** displayed adoption date is bit-stable across zone moves.
- **Compact layout:** maximum-width names (wide CJK, emoji sequences) on widget
  chrome, buttons, and notification action titles hit their specified fallbacks.

#### Deferred (not in v1 of this feature)

- Pronoun selection for the pet (copy currently avoids third-person pronouns where
  possible; a they-default is used otherwise).
- Multiple pets / pet switching.
- Name on shareable cards — arrives with Feature 3 (letters), which owns the share
  surface.

---

### Feature 2 — Anniversaries & memory callbacks

> 🆕 **v0.7 — RESOLVED** *(revised after review: the mood gate now evaluates a named
> **`RundownEmotionalRegister`** — predicted *baseline* at fire time incl. projected
> taper, never the buffer-lifted displayed mood; the comparative recovery example
> that broke the template ban is replaced and the recovery family's banned slots are
> enumerated; the streak/anniversary yield is a **general same-date collision rule**
> with one canonical priority list (streak first — no second source of truth);
> fact-age floors separate from relationship age; **once-until-changed fact
> identity** replaces the 30-day cooldown, with canonical cross-type `factId`s;
> best-day distinct-identity + tie-aware wording; date-echo "whole list" claim
> removed as unsupported by data; recovery meaningful-lateness qualification;
> `bestStreakAchievedOn` contract pinned + same-streak celebration suppression;
> a full deterministic **selection contract**; only scheduled callbacks consume
> cadence; `callback_evaluated` denominator event; the device-local duplicate
> limitation stated honestly).* Sparse relationship milestones from `adoptedOn`,
> plus occasional positive historical facts, delivered entirely on existing rails:
> the morning rundown and `CelebrationCenter`. **No new notification class, no new
> slots, no new push.**

#### Intent

Anniversaries give the relationship a visible timeline ("one month with Nori"), and
the one-year mark is the moment cancelling starts to feel like giving away a pet.
Callbacks are the harder, subtler half: recalling a concrete past win to a user who
needs it — *belief, not pressure*. The design risk is that any past-glory fact shown
during a slump silently becomes "you used to be better," which is the guilt ledger
wearing a fond expression. The register rules below exist for exactly that line.

#### Locked decisions

- **Milestone set: 1 week, 1 month, then yearly.** Sparse on purpose, mirroring
  streak milestones. Pure date-only math from `adoptedOn` (no stored schedule, no
  state): today's local date equals the milestone date → it's the day; surfaces
  compose it, and after the day nobody does. Calendar-clamped like the platform
  clamps: adoption on Jan 31 → month mark Feb 28/29; adoption on Feb 29 → yearly
  mark Feb 28 in non-leap years. **Deliberately not remote-tunable** — calendar
  facts, not levers.
- **Delivery = rundown opener line + `CelebrationCenter` banner.** The rundown line
  leads the day's priorities ("One month with Nori today"); the in-app banner shows
  on the day's first open. Celebrations remain in-app only (v0.6.1 locked) — the
  rundown line is the only notification-borne surface, and it rides the existing
  rundown class and slot.
- **General same-date collision rule: a streak milestone owns the day.** When a
  streak milestone and a relationship anniversary are eligible on the **same local
  date**, the streak milestone owns the banner and the rundown; the anniversary is
  suppressed on those surfaces and may be remembered in the week's letter ("Seven
  days of streak, one week of us"). The rule is written for *any* same-date pair —
  it does **not** assume day-7 and week-1 coincide: depending on `StreakTracker`'s
  first-active-day semantics they may land adjacent instead, in which case both
  surface normally on their own days. Anniversaries are never *deferred* to a free
  day — announcing a date on the wrong date is a small lie, and the letter already
  remembers it honestly.
- **One canonical rundown priority, one source of truth (refines Feature 4):**
  **streak milestone > anniversary > "crushed yesterday" > callback > observation.**
  One Personal-Layer line per rundown, ever. The collision rule above is this list
  applied to the banner as well.
- **Vacation: month-and-larger anniversaries get a past-tense acknowledgment after
  re-entry; the 1-week mark is skipped.** "Truly silent" holds absolutely during the
  trip. The **first post-re-entry rundown** may carry "While you were away, you and
  Nori passed the one-month mark" — honest about the date, warm about the moment,
  computable deterministically from the interval log (no stored deferral state). A
  1-week anniversary passed on vacation is too small to backdate; the letter's
  milestone beat may note it **only if a letter otherwise exists** (a fully
  vacation-covered period still produces no letter). **If the rundown toggle is off,
  a deferred acknowledgment is skipped, deliberately** — no new surface is invented
  for it.
- **Lapse: anniversaries are skipped entirely and never backdated.** No rundowns run
  while lapsed anyway, and "you missed our anniversary" on resubscribe is guilt
  manufacturing — the winback doctrine's strictest read applies. On reactivation the
  next *future* milestone is simply the next one that arrives.
- **Callbacks surface in the rundown only (v1).** Letters already have their own
  short-memory beats; the Journal timeline (Feature 6) will hold moments ambiently.
  One surface, one register, no overlap.
- **The mood gate evaluates `RundownEmotionalRegister` — predicted *baseline* at
  the rundown's fire time, including projected taper state.** Computed during
  re-lay from the same forecast the rundown already evaluates at fire time
  (`RundownRanker` precedent). Explicitly **not** the current mood at scheduling
  time, and **not** the buffer-lifted *displayed* mood: a pet or treat must not
  temporarily unlock trophy copy for an anxious user, and the comfort buffer is
  device-local — gating on it would let two devices choose different registers.
  Baseline task pressure is the stable, synced input. Tiers: **content and above**
  → any callback type; **uneasy / anxious** → recovery only — the one fact that
  helps while behind, because it is *about* getting out; **floor / chronic-taper
  days** → none (the taper's pure-presence copy owns that register; a trophy shelf
  helps nobody at the floor).
- **Facts must clear evidence floors, a fact-age floor, and be true.** Evidence
  floors per type (taxonomy below). **Fact age is separate from relationship age:**
  a memory must be old enough to *be* one — best-day and recovery facts ≥
  `callback_fact_age_days` (7) old; a streak-era record achieved ≥ 7 days ago
  unless the run has since ended; date echo is date-bound and exempt. On day 21,
  yesterday's five completions do not produce "Nori still remembers." Facts draw
  from the same 132-day fetch Feature 4's replay already makes — no new query.
- **A fact is told once — until it materially changes.** The 30-day cooldown is
  replaced: an exact fact appears in rundown callbacks **once**, becoming eligible
  again only when its identity changes (a new best-day date, a new recovery
  episode, a newly exceeded streak record, each date-echo occurrence). A best day
  retold monthly reads as an algorithm, not affection. Identity is a canonical
  **`factId`, independent of callback type**, so the same completion day can't
  reappear as "best day" and again as "date echo": `completion-day-{localDate}` ·
  recovery: stable hash of contributing task/series ids + window start ·
  `streak-record-{count}-{achievedOn}`.
- **Only a callback that is actually selected and scheduled consumes cadence** (the
  weekly cap, the gap, the fact's once-ever state). A callback that loses to a
  streak milestone, anniversary, or "crushed yesterday" stays fully eligible — a
  lost date echo being the one exception: it expires silently on its date, never
  backdated.
- **Cadence:** ≤ 1 Personal-Layer line per rundown (the canonical priority), ≤
  `callback_weekly_cap` (2) per week, ≥ `callback_min_gap_days` (3) between
  scheduled callbacks, activation only after `callback_min_age_days` (21) of
  relationship — no day-3 nostalgia.
- **Surfacing state rides the shared surfacing ledger** (Feature 4 machinery:
  per-UID, versioned, cadence-only). **Honest limitation, accepted for v1: the
  ledger is device-local, so once-ever and the caps are per-device guarantees** —
  a second device may independently tell the same fact once. The line is identical
  by determinism, so the duplicate is repetitive rather than confusing. Syncing a
  compact callback history is the v2 escape hatch if account-wide narrative
  consistency proves worth the state.

#### Callback taxonomy (v1)

| Type | Fact | Evidence floor | Example register |
|---|---|---|---|
| **Best day** | the standout completion day in the horizon | ≥ `callback_best_day_min` (5) completions from ≥ 5 **distinct tasks/series** that day; deterministic tie rule (latest qualifying day wins); tie-aware copy — a unique max is "your biggest day," a tied max is "one of your biggest days" | "A couple of weeks ago you cleared seven things in one day. Nori still talks about it." |
| **Recovery** | a genuine dig-out: overdue tasks cleared within a short span | ≥ 3 overdue tasks from **distinct tasks/series** cleared inside 48h, **and at least one was ≥ 24h overdue** (three barely-late tasks don't mint a dig-out). Lighter than Feature 4's comeback trait on purpose: this recalls one true episode, it doesn't declare a personality | "You've found your way through a pile before. Nori remembers." The only type eligible below content |
| **Streak era** | best streak (count always; era phrasing only with `bestStreakAchievedOn`) | best ≥ 7; **suppressed while the record belongs to the currently active streak and that streak produced a milestone celebration within `callback_streak_quiet_days` (14)** — day 30 must not be congratulated and then "remembered" a week later | "Your longest run together is 23 days." |
| **Date echo** | same-date memory ("a month ago today…") | the referenced day clears the best-day floor (incl. distinct identities) | "A month ago today you finished seven things." **Never** "cleared your whole list" — completion records prove counts, not that the open list was empty; no claim the data can't support |

Deliberately small; each type has its own pool (4–6 lines, rotation per the v0.4
copy mechanics, pet-name templated). Coarse relative time in rundown lines ("a
couple of weeks ago"); precise dates reserved for letters. Counts are permitted in
best-day and date-echo copy — **never in the recovery family** (below).

**The recovery template family is structurally restricted** (same mechanism as the
rough-letter set — restrictions live in what the templates *can* say):

- no slots for current or past completion/overdue counts,
- no past-versus-current magnitude ("bigger than", "more than", "worse than"),
- no "back to", "used to", "back when", or localized equivalents,
- "again" only ever attaches to resilience ("you've done this before"), never to
  volume,
- no reference to the user's present pile at all — the *user* knows why the line is
  showing up; Mochi just believes in them.

#### Selection contract (deterministic)

When multiple callbacks qualify for one rundown slot:

1. **Type priority: date echo > recovery > best day > streak era.** Date echo
   expires today and cannot wait; recovery is the most emotionally useful; streak
   era is the most static and can always wait. Below content, recovery is the only
   candidate by the register gate.
2. **Within a type:** a never-told fact beats a told-and-since-changed one; then
   the most recent qualifying fact; ties resolve by stable `factId` ordering.
3. **Only the winner consumes cadence state.**

The whole selection is a pure function of (facts, register, ledger cadence state,
date) — two evaluations on the same device agree; cross-device agreement holds for
everything except the device-local cadence inputs, per the stated limitation.

#### `bestStreakAchievedOn` contract

- Date-only, same calendar semantics as the streak engine.
- Updated **atomically with `bestStreakCount`**, and only when the count is
  **strictly exceeded** — equal values never overwrite the date. As an active
  record-setting streak advances daily, the field advances with it: it is the date
  the currently stored record was first reached.
- Legacy records are **never assigned a guessed date** — a legacy user gets
  count-only copy until a new record is set after the field ships.

#### Remote Config

`callback_weekly_cap` 2 · `callback_min_gap_days` 3 · `callback_min_age_days` 21 ·
`callback_fact_age_days` 7 · `callback_best_day_min` 5 ·
`callback_streak_quiet_days` 14 — joining `RemoteTuning` under the standard rules.
(The 30-day repeat cooldown is gone — once-until-changed replaced it. The milestone
set is deliberately not remote-tunable.)

#### Edge-case matrix

| # | Situation | Behavior |
|---|---|---|
| 1 | Streak milestone + anniversary, same local date | Streak owns banner + rundown (general collision rule); anniversary suppressed there; letter may carry both in one beat |
| 2 | Day-7 streak and week-1 anniversary land on *adjacent* days (StreakTracker semantics) | No collision — both surface normally on their own days; the rule never assumed simultaneity |
| 3 | Month/yearly anniversary during vacation | Past-tense acknowledgment in the first post-re-entry rundown; derived from the interval log, no stored state |
| 4 | Deferred acknowledgment + rundown toggle off | Skipped, deliberately — no new surface is invented for it |
| 5 | 1-week anniversary during vacation | Skipped (too small to backdate); letter may note it only if a letter exists for that period |
| 6 | Anniversary during lapse | Skipped entirely, never backdated — winback purity |
| 7 | Adoption Jan 31 / Feb 29 | Month mark Feb 28/29; yearly mark Feb 28 in non-leap years (calendar clamps) |
| 8 | Rundown toggle off on an anniversary day | `CelebrationCenter` banner still shows in-app; callbacks don't fire (rundown-only) |
| 9 | Notifications denied | Rundown undelivered; banner carries the anniversary on first open |
| 10 | Floor / chronic-taper morning (projected register) | No callback; taper presence copy owns the register. Anniversary lines still show — a date is not a demand |
| 11 | Anxious user pets Mochi right before re-lay | Register unchanged — the gate reads predicted *baseline*, not the buffer-lifted displayed mood; comfort can't unlock trophy copy |
| 12 | Two devices, different comfort buffers | Same register on both — baseline is synced-data-deterministic; only cadence state is device-local |
| 13 | Day 21, best day was yesterday | No callback — fact-age floor (7 days); relationship age alone doesn't make a memory |
| 14 | Best day unchanged for months | Told once, then silent — once-until-changed; a new best-day date is a new fact |
| 15 | Same date qualifies as best day and date echo | One `factId` (`completion-day-{localDate}`) — told once across both types |
| 16 | Tied best days | Deterministic tie rule picks; copy says "one of your biggest days," never a false superlative |
| 17 | Three tasks each 15 minutes late, cleared together | Not a recovery — the ≥ 24h-overdue qualification fails; directionally late ≠ dug out |
| 18 | Streak hits 30, celebration fires, callback considers the same run | Streak-era suppressed for `callback_streak_quiet_days` (14) while the record belongs to the active run — congratulate, don't immediately "remember" |
| 19 | Legacy profile without `bestStreakAchievedOn` | Count-only copy; era phrasing gated until a new record stamps the field; no guessed dates ever |
| 20 | Callback loses the slot to an anniversary | Stays fully eligible (didn't consume cadence); a losing *date echo* expires silently instead — never backdated |
| 21 | Two devices, callback cadence | Each may tell a given fact once (device-local ledger) — accepted, documented; identical lines by determinism |
| 22 | Timezone travel around an anniversary | "Is today the day" checks the current local date against the date-only milestone; can shift by hours at a boundary — accepted, same class as the scheduler |
| 23 | Deferred vacation acknowledgment meets re-entry celebration | No collision: welcome-back is the in-app moment at re-entry; the acknowledgment rides the next morning's rundown |

#### Instrumentation

- `anniversary_shown`: milestone tier + surface (banner / rundown / deferred).
- `callback_shown`: type + register tier at lay time.
- `callback_evaluated` — the denominator (the Feature 4 lesson, applied): type +
  qualified bool + coarse register tier + **coarse blocked reason** (no fact /
  evidence / fact age / register / priority / gap / weekly cap / already told), at
  most once per type per user-day. Without it, "callbacks are scarce" can't be told
  apart from healthy sparsity, tight floors, or priority starvation.
- **No payloads anywhere** — no dates, counts, streak values, or fact identifiers.
- Tripwire (alert-only, human-reviewed), now answerable with the denominator: if
  the caps are the binding constraint for most users the gates are too loose; if
  facts almost never qualify the floors are too tight.

#### Test coverage (required)

- **Date math:** clamps (Jan 31, Feb 29), yearly recurrence, date-only comparison
  across zone changes.
- **Collision rule:** same-date streak + anniversary resolves to streak on banner
  and rundown; adjacent days both surface; letter beat may carry both; priority
  list table-driven with streak first.
- **Register gate:** computed from predicted baseline + projected taper at fire
  time; buffer lift changes nothing; the three tiers gate types correctly.
- **Vacation deferral:** month+ acknowledged past-tense on first post-re-entry
  rundown from intervals; 1-week skipped; toggle-off skips deliberately; nothing
  during the trip.
- **Lapse:** skipped, never backdated; next future milestone resumes.
- **Fact identity:** once-until-changed per canonical `factId`; cross-type dedup
  (best day vs. date echo); new date / new episode / strictly-new record re-arm.
- **Evidence floors:** per-type table-drive incl. distinct-identity requirements,
  recovery's ≥ 24h-overdue qualification, fact-age floors, tie rule + tie-aware
  copy selection.
- **`bestStreakAchievedOn`:** atomic with count, strictly-exceeded only, equal
  never overwrites, legacy never guessed; same-run celebration suppression window.
- **Selection contract:** type priority, within-type ordering, only-winner-consumes,
  losing date echo expires; determinism (same inputs + date → same line).
- **Register templates:** recovery family structurally contains no slots for
  counts, magnitude comparison, or the banned constructions (assert on templates,
  same mechanism as the rough-letter test).

#### Deferred (not in v1 of this feature)

- Half-year marks or "100 days together" (sparse set first; density is easy to add
  and impossible to remove gracefully).
- Callback surfaces beyond the rundown (Journal moments belong to Feature 6).
- Synced callback history for account-wide once-ever (the stated v2 escape hatch).
- A yearly-letter tie-in (year-in-review letter is Feature 3's noted v2).

### Feature 3 — Weekly letter from Mochi

> 🆕 **v0.7 — RESOLVED** *(revised after review: the **letter period** replaces the
> naive calendar week — the Sunday-19:00 send vs. "closed Mon–Sun week" contradiction
> is resolved by an explicit cutoff at send time; period-start date ids (no ISO
> week-year trap) under one authoritative timezone; an **online composition barrier**
> so first-writer-wins can't commit over stale inputs; a deterministic engagement
> input (`activityWeeks` marker) behind the dormant-skip; structural vs. optional
> beat selection with a single insight-family cap; **both share variants rendered at
> composition** from structured beat data; rough-week template restrictions with the
> numeral scan demoted to backstop; letter notifications scheduled only for
> already-non-dormant periods; diagnostic-grade open-rate instrumentation).*
> The flagship: a Sunday-evening recap in Mochi's monologue voice, composed once as
> an immutable artifact, archived, shareable as a rendered card.

#### Intent

The letter is the ritual a subscriber would lose by cancelling, and the accumulated
archive is the relationship made visible. It is also the app at its most
philosophically exposed: a rough week's letter is the moment the product either
proves "Mochi is sad *with* you, never *at* you" or becomes a report card. Every rule
below exists to make the warm outcome structural, not aspirational.

#### The letter period

A **letter period** begins Monday 00:00 and ends at the **effective send time** on
Sunday — `letter_send_hour` (19:00), or the bedtime clamp if earlier. The period end
*is* the cutoff: completions after it belong to the next period. This makes the
Sunday-evening ritual and the "compose only over a closed period" rule
simultaneously true (a full Mon–Sun calendar week would make Sunday-evening
composition a contradiction; the ritual is worth more than Sunday's last hours).

- **Identity:** `letter-{periodStart}` with the period's Monday as a plain date
  (`letter-2026-07-20`). Deliberately **not** `yyyy-Www` — calendar year and ISO
  week-based year diverge around New Year, and a date-based id has no formatter
  traps.
- **Authoritative timezone:** period boundaries and identity derive from the
  **synced profile `timezone`**, read server-backed during the composition barrier —
  never from whichever zone a device happens to be in. A phone and iPad near a zone
  boundary must identify the same previous period, or one-letter-ever fails.
- `periodStart`, `periodEndExclusive`, and the timezone used are **stored on the
  letter document** — no later ambiguity about what the letter covered.

#### Locked decisions

- **A letter is an immutable artifact of a closed period, composed exactly once.**
  Written **create-only** to Firestore; first composer wins, every other device
  reads. Once written it never changes: not for later widget drains, not for Remote
  Config or copy-deck updates, not for task deletions or a pet rename. A letter is a
  postcard, not a view.
- **First composition requires the online barrier.** Determinism over stale inputs
  is worthless: a device with pending widget completions, an unsynced archive, or an
  old interval log would deterministically compose the *wrong* letter and win the
  race. Therefore composition **cannot commit offline**: flush pending local writes,
  obtain server-backed completion/interval/archive/profile state, then create inside
  a Firestore transaction with an existence precondition; if the create loses,
  discard the local result and display the winner. Only first composition carries
  this contract — reading the archive works offline like everything else.
- **A bad period never produces a bad letter — structurally, at the template
  level.** Rough-period letters draw from a formally restricted template set:
  **no quantified facts, no task-title interpolation, no observation interpolation,
  no ask.** The no-numerals scan on rendered output remains as a *backstop test*,
  not the policy (a regex catches "3" but not "three", and would false-trip on
  titles like "Form 1099" — which the template restriction keeps out entirely).
  On-time percentages and miss counts never appear in any letter (guilt-ledger
  rule). Ship test unchanged: would this make someone at the floor feel worse?
- **Letters may name tasks and cite counts** (outside rough periods) — composed from
  closed-period data at read time, so the staleness rule that keeps mood pings vague
  does not apply. **No emoji** (prose surface; VoiceOver reads it aloud).
- **A letter about nothing is worse than no letter.** Skip silently when the period
  predates the first full period after `adoptedOn`, or when the period was
  **dormant**: zero completions *and* no user-visible foreground session (a dormant
  user gets no "we noticed you were gone" — winback pressure by another name). A
  *quiet* period for a user who showed up still gets a letter: short, warm, zero
  ask — nothing was wrong. Dormancy is decided by a **deterministic product input**,
  never Analytics (see Inputs).
- **Vacation periods: no letter.** A period fully inside vacation composes nothing;
  "truly silent" extends to the letter's notification. A partial-vacation period
  gets a letter whose vacation beat acknowledges the trip warmly and **never**
  inventories what piled up (the triage sheet owned that). Skipped letters are never
  backfilled.
- **Lapsed: no letters, no backfill on return.** The archive stays readable (it's
  theirs). Letters resume with the first full period after reactivation.
- **The notification is an invitation, never the delivery.** The letter becomes
  available on the **next eligible foreground**, regardless of notification
  permission or delivery — under the local-notification architecture the app
  generally cannot execute composition just because a scheduled notification fired
  while it was closed. **Scheduling invariant: a letter notification is laid only
  once its period is already non-dormant** — the planner never queues a Sunday
  invitation for someone who may then vanish all week.
- **Both share variants are rendered at composition and stored.** The private
  variant is composed independently from structured beat data — never by string
  surgery on immutable prose (a task may since be deleted, renamed, or contain text
  that can't be safely replaced). The stored **pet-name snapshot** drives the
  signature and card forever; renaming the pet never edits old postcards.
- **Sharing defaults to the private variant.** Including task names is a per-share
  opt-in. Sharing is outward-facing — the cautious default is the only safe one.

#### Inputs (all deterministic)

`LetterComposer` is a pure function over a `PeriodSummary`:

- the period's completion records (with local context, per Feature 4's model),
- **`hadUserForeground: Bool`** — from a synced, **create-only weekly engagement
  marker** (`users/{uid}/activityWeeks/{periodId}`), written on the first
  user-visible foreground session in the period. A notification tap counts (the
  user intentionally entered); background refresh, notification scheduling, and
  widget draining do **not**. Product data the composer reads deterministically —
  never derived from Analytics,
- streak state + milestones landed during the period (`StreakMilestones`),
- `QualifiedObservation`s (Feature 4 — the only insight input; candidates can't
  reach it by type),
- vacation/lapse intervals overlapping the period (the Feature 4 interval log),
- trailing 4-period completion average (for classification),
- pet name + `adoptedOn` (Feature 1),
- prior letters' beat/line ids (from the archive — powers deterministic rotation).

No clock reads, no timezone reads, no randomness inside the composer: "now," the
calendar, the period boundaries, and the authoritative zone arrive as parameters
(the Feature 4 purity rule, applied again). Line variety needs no stored rotation
state — variant selection is `hash(periodId, beatType)` over the pool, with a
don't-repeat-last-N check against the synced archive, so it is deterministic *and*
device-independent.

#### Period classification

Classified from task facts only (no mood-replay dependency), evaluated on the closed
period:

| Class | Rule (defaults, Remote Config) | Register |
|---|---|---|
| **Great** | completions ≥ 1.5× trailing average, and ≤ 1 day with overdue tasks | Celebratory; numbers welcome |
| **Steady** | everything not matching another class | Warm, specific |
| **Quiet** | ≤ `letter_quiet_max` (2) completions and ≤ 2 tasks due all period | Short, cozy; nothing was wrong |
| **Rough** | ≥ `letter_rough_overdue_days` (4) days with overdue tasks, or completions < 25% of trailing average with tasks due | Presence; the chronic-floor voice; restricted template set |
| **Vacation-partial** | vacation covered part of the period | Warm trip acknowledgment; never inventories the pile |

Precedence: vacation-partial > rough > great > quiet > steady. (A rough period that
ends in a vacation start is a vacation-partial letter — rest was the right call, and
the letter treats it that way.)

#### Beat library v1

Structure: **salutation → 2–3 beats → closing → signature** ("From Nori", from the
pet-name snapshot). Body length 40–120 words; each beat 1–2 sentences.

**Selection is two-phase — structural beats are not priorities:**

1. **Insert the required structural beat** for the class: rough → **presence,
   first**; vacation-partial → **vacation**; quiet → the **quiet beat** (its only
   beat). Structural beats can never be displaced by optional ones.
2. **Fill remaining slots** from the optional beats by priority, up to
   `letter_max_beats` (3; rough caps at 2), with one beat per category and **at most
   one insight-family beat total (observation *or* list return, never both)** — a
   three-beat letter must not contain two separate "Mochi analyzed you" moments.

| | Beat | Kind | Eligibility | Notes |
|---|---|---|---|---|
| 1 | **Milestone** | optional | streak milestone or anniversary landed this period | References the moment as shared memory ("Thirty days together this week") — never re-announces what `CelebrationCenter` already celebrated |
| 2 | **Comeback moment** | optional | an overdue task was cleared this period | The single biggest recovery, named: "That dentist call had been waiting a while. You got it Tuesday." Post-action by definition |
| 3 | **Best day** | optional | a day with ≥ 3 completions and the period's max | "Thursday was a big one. Six things done and Nori danced." |
| 4 | **Observation** | optional (insight family) | a `QualifiedObservation` not surfaced in a rundown this week (Feature 4's dedup rule) | Excluded from rough periods |
| 5 | **List return** | optional (insight family) | Feature 4's list-return event fired this period | Its primary surface, per Feature 4 |
| — | **Presence** | **structural** (rough) | always available | Chronic-floor register: one small true positive if any exists, zero ask. "This week was heavy. Nori stayed close." |
| — | **Vacation** | **structural** (vacation-partial) | — | "You were away, and resting counts." |
| — | **Quiet** | **structural** (quiet) | — | Salutation + one cozy beat + closing — the shortest letter in the system, by design |

#### Delivery & surfaces

- **Notification:** stable ID `letter-{periodStart}`, `.active`, its own toggle in
  notification prefs ("Weekly letter"), fires at the period end (Sunday
  `letter_send_hour` 19:00, bedtime-clamped — the clamp *moves the cutoff*, which is
  why the period end is stored per letter). Laid by the planner in the normal
  re-lay **only once the period is non-dormant** (the scheduling invariant). Budget
  order: **promises → mood pings → rundowns → letter** (the letter drops first under
  slot pressure; it alone has a full in-app backstop). Suppressed entirely during
  vacation and lapse. Never counts against the mood-ping cap.
- **In-app:** an unread letter shows a quiet envelope indicator on Home (near Mochi,
  not a badge-red demand). **The archive is owned by the Personal Layer, not by
  "You":** `LetterArchiveView` + `LetterArchiveViewModel` ship now, routed from a
  temporary "Letters" row in "You"; Feature 6 re-routes the same destination from
  the Journal tab and retires the row — a navigation change, not a data or UI
  migration.
- **Reading state** (`readAt`) is per-letter, synced (it's on the letter doc), so a
  letter read on the phone doesn't re-flag on the iPad.

#### Storage

`users/{uid}/letters/{letter-{periodStart}}`:

```
periodStart, periodEndExclusive, timeZone     // the period contract, pinned
classification
beatTypes + lineIds                           // rotation + payload-free debugging
fullRenderedText, privateRenderedText         // both variants, composed together
petNameSnapshot                               // signature + card, forever
composedAt
composerVersion, copyDeckVersion,
periodSummaryHash                             // provenance (hash non-reversible)
readAt?                                       // the ONE mutable field
```

Create-only by security rules (same enforcement pattern as `adoptedOn`; `readAt`
sole exception). Letters ride the account: synced across devices, destroyed with
the subtree on account deletion. Everything inside a letter is a snapshot — task
deletion, rename, or pet rename never edits the postcard.

#### Sharing

`ImageRenderer` card (the Feature 1-deferred share surface, landing here): letter
text, the period-register Mochi pose, adoption-age line ("With Nori since March",
from the snapshot), small wordmark. **Private (default):** the stored
`privateRenderedText` — task names already replaced with neutral phrasing at
composition ("a big one you'd been putting off"). **Full:** per-share opt-in,
serving the stored `fullRenderedText`. Rough-period letters share like any other
(they're often the most moving artifact) but only as private — full is not offered.

#### Remote Config

`letter_send_weekday` 1 (Sunday) · `letter_send_hour` 19 · `letter_max_beats` 3 ·
`letter_quiet_max` 2 · `letter_rough_overdue_days` 4 · `letter_great_ratio` 1.5 —
joining `RemoteTuning` under the standard clamping/publication/pinning rules.
Constants land at compose time and are baked into the stored letter; a later tuning
pass changes future letters only.

#### Edge-case matrix

| # | Situation | Behavior |
|---|---|---|
| 1 | First partial period after adoption | No letter (needs one full period); in-app day-1 delight carries the early experience |
| 2 | Dormant period (zero completions, no user foreground) | Skip silently — no letter, no notification, no "we missed you". The `activityWeeks` marker is the deterministic arbiter |
| 3 | Quiet period, user showed up | Short quiet letter — warmth without manufactured content |
| 4 | Rough period | ≤ 2 beats, presence structural and first, restricted template set (no quantified facts / task titles / observations / ask) |
| 5 | Completion on Sunday at 20:30, after the cutoff | Belongs to the next letter period — by definition, not by accident |
| 6 | Period spanning New Year | Date-based id (`letter-2025-12-29`) — immune to the calendar-year vs. ISO-week-year mismatch |
| 7 | Phone and iPad in different timezones at compose time | Period identity derives from the synced profile timezone (read server-backed), not device zones — both identify the same period |
| 8 | Device offline all Sunday | No composition until the online barrier passes; the letter appears on the next connected foreground. Late is acceptable; wrong is not |
| 9 | Two devices race Monday morning | Both pass the barrier; transaction with existence precondition — one letter; the loser discards its local result and displays the winner |
| 10 | Device with pending widget completions tries to compose | The barrier's flush happens first — the letter can't be composed blind to the user's own completions |
| 11 | Period fully inside vacation | No letter, no notification; never backfilled |
| 12 | Vacation starts or ends mid-period | Vacation-partial letter; acknowledges the trip; never inventories what came due |
| 13 | Lapse during the period | No letter; archive stays readable; resumes first full period after reactivation |
| 14 | Milestone and anniversary in the same period | One milestone beat references both; `CelebrationCenter` announces, the letter remembers |
| 15 | `letter_send_hour` inside the bedtime window | Clamp moves both the notification *and the cutoff* (they are the same instant); stored `periodEndExclusive` records it |
| 16 | Notifications denied or letter toggle off | Letter becomes available on next eligible foreground with the Home indicator; reading never depends on push |
| 17 | 64-slot pressure | Letter slot drops first; the in-app path is the backstop |
| 18 | Widget completion drained after composition | Letter immutable; the completion counts toward the next period. Accepted, documented |
| 19 | Task named in a letter later deleted/renamed; pet renamed | Letter (both variants) and signature unchanged — snapshots |
| 20 | Rough-period task titled "Form 1099" | Never in the letter — the restricted template set forbids title interpolation; the numeral backstop can't false-trip on it |
| 21 | Streak frozen by vacation during the period | The letter never says a streak broke (freeze semantics); milestone math uses the frozen value |
| 22 | RC constants or copy pools change after composition | Stored letters untouched; future letters pick up the change |
| 23 | Account deletion | Letters and `activityWeeks` markers destroyed with the subtree |

#### Instrumentation

Diagnostic-grade, because a raw rough-vs-great open-rate comparison confounds tone
quality with mood-correlated usage and notification routing:

- `letter_composed`: classification + beat types + word-count bucket. Never text,
  task names, or observation payloads.
- `letter_indicator_shown`: the Home-envelope impression — the denominator an
  open-rate needs.
- `letter_opened`: **source (notification / Home / archive)** + classification +
  time-to-open bucket + whether a notification had been scheduled + whether this
  user has previously opened letters.
- `letter_shared`: variant only.
- **Evaluation method:** compare opens *after a Home-envelope impression*, and
  prefer within-user comparisons (the same user's rough letters vs. their own
  steady/great letters). Minimum sample floor + confidence interval before any
  alert. A rough-period gap is a signal to inspect copy and usability — **a
  diagnostic, not a verdict** on the presence voice. Alert-only, human-reviewed,
  same tripwire doctrine as everything else.

#### Test coverage (required)

- **Period contract:** cutoff attribution (Sunday 20:30 → next period), bedtime
  clamp moves the cutoff, `periodStart`/`periodEndExclusive`/zone stored and
  round-tripped.
- **Identity:** date-based ids across New Year; same period id from devices in
  different zones (authoritative profile timezone).
- **Classification table-drive:** each class, precedence, boundary values (exactly
  1.5×, exactly 4 overdue days), trailing-average edge (fewer than 4 periods of
  history).
- **Composer determinism:** same `PeriodSummary` → byte-identical letter (both
  variants); no hidden clock/zone/randomness.
- **Structural selection:** structural beats inserted first and never displaced;
  rough beat cap; insight-family cap (observation XOR list return); quiet
  single-beat form.
- **Rough template restriction:** restricted set contains no interpolation slots
  for titles/observations/quantities (structural assert on templates), plus the
  numeral scan as backstop on rendered output.
- **Rotation:** don't-repeat-last-N against a seeded archive; deterministic across
  devices.
- **Gating:** first-period skip, dormant skip (marker-driven), full-vacation skip,
  lapse skip; no backfill in any of them; `hadUserForeground` set by foreground and
  notification tap, not by background refresh / scheduling / widget drain.
- **Composition barrier:** offline composition blocked; pending writes flushed
  first; transaction existence precondition; loser discards and displays winner;
  provenance fields written.
- **Immutability:** updates (except `readAt`) rejected by rules; task/pet renames
  alter nothing; both variants stored at compose time.
- **Scheduling:** fire at period end; laid only for non-dormant periods;
  budget-order drop; vacation/lapse suppression; denied-permission in-app path.
- **Sharing:** private variant is the stored render (no string surgery); full is
  opt-in; rough periods never offer full.

#### Deferred (not in v1 of this feature)

- List-spotlight beat ("Work got a lot of love this week") — needs per-list volume
  norms to avoid crowning the same list weekly; revisit with acceptance data.
- Monthly / yearly letters (the anniversary letter is Feature 2's rundown beat for
  now; a year-in-review letter is an obvious v2 with real archive data behind it).
- User replies or reactions to letters (a delightful idea with real scope — a
  relationship channel needs moderation-grade thought).
- Letter localization beyond the String-Catalog readiness all copy already has.

### Feature 4 — Mochi's observations (insight engine)

> 🆕 **v0.7 — RESOLVED** *(revised after review — statistical-integrity pass:
> completion-local time captured at the source (travel can no longer rewrite apparent
> behavior), canonical minute-level distribution with bands as derived views,
> **deterministic hysteresis** replacing ledger-stored stickiness (cross-device
> agreement by construction), switch/retire transitions + per-type stability
> policies, evidence-spread gates (distinct weeks/dates + per-day caps) against
> single-burst false positives, momentum vacation/lapse normalization fixed with an
> interval-log input, **list attention removed** in favor of a positive list-return
> observation, comeback evidence strengthened, provenance-carrying distribution API,
> candidate/qualified type split, `observation_evaluated` denominator event, per-UID
> ledger namespacing, algorithm versioning).* The "most productive times" idea with
> the register shifted: not analytics the app displays, but things Mochi *noticed*.
> A pure engine with no UI of its own; it surfaces through Features 3 (letter beats),
> 2 (rundown lines), 6 (Journal card), and feeds Feature 5 (suggested times).

#### Intent

The single most "it gets me" moment available from data the app already stores is
Mochi telling the user something true about themselves: *"You get the most done on
Tuesdays. Nori noticed."* The same datum rendered as a chart is Screen Time; rendered
as the pet's attention it is a relationship. **Statistical integrity is therefore the
product feature, not an engineering nicety:** one false "you're a morning person" —
earned from a single bulk-cleanup session or a timezone artifact — breaks the
illusion the entire layer sells. Every rule below that looks like statistics is
actually brand protection.

The engine's second job is being the **canonical statistical source** for Feature 5,
so a suggestion chip and a letter line always derive from the same facts about the
user.

#### Locked decisions

- **When unsure, say nothing.** Confidence gating *is* the feature. Every observation
  type has minimum-evidence, evidence-**spread**, and margin requirements; failing any
  produces silence, never a hedged guess. There is no "not enough data yet" copy.
- **Framings are always neutral-to-positive.** A falling completion trend produces
  **no observation** (not a concerned one). "You reschedule a lot" is expressible only
  as Feature 5's useful suggestion, never as prose. Negative patterns are not
  observations; they are silence. (The guilt-ledger rule, applied to inference.)
  **List attention — "the Personal list has been waiting quietly" — is removed under
  this rule:** however warm the copy, it names inaction and assigns emotional
  presence to neglected work, which lands as guilt in exactly the fragile week the
  rule protects. Its replacement, **list return**, fires only *after* action.
- **Completion-local time is captured at the source.** Every native completion stores
  its local calendar date, minute-of-day, and IANA timezone *at the moment of
  completion* (including widget-drain completions, which stamp local context into the
  App Group queue **at completion time, not drain time**). Behavior is a fact about
  when the user acted *in their day*; re-deriving it later from an absolute timestamp
  plus the device's *current* zone lets travel rewrite history. Historical and
  Apple-sourced completions, where the original zone is unrecoverable, fall back to
  interpretation under the current zone — a documented degradation that decays out of
  the window, not a permanent model.
- **The canonical distribution is minute-level; every bucketing is a derived view.**
  The engine's stored representation is raw `completedLocalMinute` values. The
  24-hour histogram, the four copy bands, and Feature 5's suggestion math are all
  *views* over the same minutes — band boundaries and bucket widths are presentation
  decisions, not storage decisions. Feature 5 computes on minutes with **circular
  time math** (23:30 and 00:30 cluster to midnight, never to noon).
- **The shared-source invariant, stated precisely:** all observation and suggestion
  outputs derive from the same canonical completion records, timezone rules, filters,
  and provenance model. It does **not** promise that a global letter line and a
  list-scoped suggestion reach the same top period — scope and weighting can
  legitimately differ; the *facts* cannot.
- **Stability is deterministic, not stored.** Whether a conclusion holds, switches,
  or retires is computed by replaying daily gate evaluations over synced completion
  data — a pure function, so **all devices agree on the conclusion by construction**.
  The ledger stores no stability state; it owns only surfacing cadence (below).
- **Conclusions switch *and* retire.** Switch: the incumbent fails its gate for
  `obs_sticky_days` consecutive daily snapshots while a challenger passes throughout.
  Retire: the incumbent fails for the same period and *no* challenger qualifies —
  the conclusion goes silent rather than lingering for months. Both transitions are
  silent (no "actually…" copy).
- **Stability policy is per-type, not universal** (table below). "More check-offs
  lately" surviving 14 days after the trend died would be a lie; a categorical trait
  flapping weekly would be a horoscope. Different lifecycles, different rules.
- **The circularity trap is designed out.** A weekly-Tuesday recurring task completed
  every Tuesday must not produce "you're productive on Tuesdays" — that would parrot
  the user's own schedule back as insight. The **weekday observation uses one-off
  completions only**. (Time-of-day keeps all completions: *when in the day* the user
  acts is genuine behavior even for scheduled tasks.)
- **Never in mood pings.** Mood pings are vague by locked v0.4 decision; an
  observation is precise by definition. Surfaces: letter beats, an occasional rundown
  line, the Journal card. Nothing else.
- **Numbers stay out of the copy.** Observation lines never contain percentages or
  counts (same instinct as hiding the raw mood value). Letters may cite counts under
  Feature 3's own rules; *observation* copy is qualitative.
- **Production surfaces can only receive qualified observations — by type.**
  `ObservationCandidate` (inspector + tests, carries gate-by-gate evidence) and
  `QualifiedObservation` (the only type surfaces accept) are separate types; a future
  UI caller *cannot* accidentally render a failed candidate.
- **Telemetry never carries conclusion payloads.** Not the weekday, not the band, not
  the `listId`. One no-payload rule for all types is simpler, safer, and future-proof
  against sensitive conclusion types.

#### Inputs

**Completion record** — `CompletedTaskStat` extends to:

```
taskId                    // internal id; enables diversity gates; never leaves the device
seriesId?                 // stable across a recurring task's occurrences
completedAt               // UTC instant (unchanged)
completedLocalDate        // YYYY-MM-DD in the zone where completed
completedLocalMinute      // 0…1439 in the zone where completed
completionTimeZone        // IANA id at completion
dueAt?, hasTime           // due semantics (timed vs date-only lateness)
listId?
isRecurring
source                    // mochi | apple
rescheduleCount: Int?     // nil = unknown (Apple) — nil ≠ 0; 0 means known-unmoved
```

Native completions populate the local-context fields at completion time (widget
drain included, stamped at completion). For pre-existing rows and Apple-sourced
completions the local fields are backfilled under the current zone and marked
derived — the documented fallback.

**Eligible-day history** — momentum normalization requires knowing which *historical*
dates were vacation or lapsed, which the app does not currently persist. An
append-only **interval log** (vacation intervals, lapse intervals) is added to the
synced profile data from this version forward — synced, because deterministic
hysteresis requires all devices to see the same inputs. **Honest-fallback rule: for
any period predating the log, momentum is silent whenever either comparison half
touches days whose eligibility is unknown.** No claimed normalization without a data
source.

**Open-task summary** — per-list open counts, due-ness, and completion history for
the list-return observation; derivable from `incompleteTasks`, no new repository
surface.

**Window:** `obs_window_days` (default **42**). Note honestly: 42 days is six
*opportunities* per weekday, not six guaranteed samples — which is exactly why the
spread gates below exist. The engine takes its calendar and timezone as **explicit
parameters** (no `.autoupdatingCurrent` read inside) — otherwise "same inputs, same
output" is false. Callers pass the device's current zone; the engine applies it only
where the model says to (fallback interpretation), never to re-bucket records that
carry their own local context.

#### The v1 observation set

Copy bands (derived views over minutes): **morning** 05:00–12:00 · **afternoon**
12:00–17:00 · **evening** 17:00–21:00 · **night** 21:00–05:00.

| Type | Conclusion | Evidence floor | Spread gate | Margin gate | Example copy register |
|---|---|---|---|---|---|
| **Productive weekday** | one weekday | ≥ `obs_weekday_min` (15) *one-off* completions | evidence from ≥ `obs_weekday_weeks` (3) distinct weeks; each calendar day contributes ≤ `obs_day_cap` (3) | top share ≥ `obs_weekday_share` (0.30) **and** ≥ `obs_margin_ratio` (1.5×) runner-up | "You get the most done on Tuesdays. Nori noticed." |
| **Productive time of day** | one band | ≥ `obs_timeofday_min` (20) completions | ≥ `obs_timeofday_dates` (5) distinct dates across ≥ `obs_timeofday_weeks` (3) weeks; day cap applies | top band share ≥ `obs_timeofday_share` (0.40) **and** ≥ 1.5× runner-up | "Mornings are when things happen around here." Night band: "Things get done after 9pm around here, and that counts just the same." |
| **Momentum** *(current-window fact, not a trait)* | rising only | each half ≥ `obs_trend_half_min` (10) completions on fully-eligible days | halves compared per-eligible-day | rate ≥ `obs_trend_ratio` (1.3×) **and** absolute delta ≥ `obs_trend_min_delta` (0.2/day) — a relative jump between two tiny rates is not a trend | "More check-offs lately. Nori can feel it." Falling = silence |
| **List return** *(event, replaces list attention)* | one list | a completion lands in a list after ≥ `obs_return_quiet_days` (14) quiet days | list has real prior history (≥ `obs_return_history_min` (5) completions before the quiet spell); quiet spell contains no vacation/lapse days | n/a — the event either happened or didn't | "You found your way back to Personal this week." Fires **after action**; celebrates the return, never notices the absence |
| **Comeback pattern** | none (trait) | ≥ `obs_comeback_min` (8) overdue-then-completed events | ≥ `obs_comeback_dates` (3) distinct completion dates **and** ≥ `obs_comeback_tasks` (3) distinct tasks/series | median overdue-to-done ≤ `obs_comeback_hours` (24) **and** p75 ≤ `obs_comeback_p75_hours` (48) — the p75 gate stops three fast saves from hiding two week-long stalls | "When something slips, you catch it fast. Nori loves that about you." |

Notes:

- **Momentum eligibility (vacation/lapse fixed):** days inside vacation or lapse
  intervals are excluded from momentum **entirely — both the day and its
  completions** (numerator and denominator together; the earlier
  keep-completions/drop-days rule inflated the rate). Weekday and time-of-day
  distributions still include vacation-day completions: *when* you act is behavior
  regardless of mode. A recent resubscription can't manufacture a rising trend,
  because lapse days are ineligible the same way.
- **Comeback lateness semantics:** for date-only tasks, overdue-to-done measures from
  end of the due day (the existing overdue rule); completing next morning therefore
  reads as a fast catch — accepted and documented, not a bug. The task/series
  diversity gate stops one habitually-slightly-late recurring task from minting the
  trait by itself.
- **List return** is deliberately an *event observation*: it has no incumbent, no
  hysteresis; it fires, surfaces within the week (letter beat first, Journal
  otherwise, never the rundown), then expires. It invalidates instantly on its own
  trigger (the return already happened).

#### Stability — deterministic hysteresis

For trait-like types (weekday, time-of-day, comeback), the current conclusion is
computed by a **deterministic replay**: evaluate the gates for each daily snapshot
(the 42-day window ending on that day) across the last `obs_replay_days` (90),
folding a small state machine forward from an empty seed:

- a candidate that passes every snapshot for `obs_sticky_days` (14) consecutive days
  becomes the incumbent;
- **switch:** the incumbent fails 14 consecutive snapshots while one challenger
  passes throughout → the challenger is the new incumbent;
- **retire:** the incumbent fails 14 consecutive snapshots and no challenger
  qualifies → no conclusion (silence).

Because the replay is a pure function over synced completion records (with their
stored local context) and the synced interval log, **every device computes the same
incumbent** — no synced stability state, no drift. The fixed replay depth is part of
the algorithm's definition (devices must fold from the same start), and the fetch
horizon is `obs_replay_days + obs_window_days`.

| Type | Stability policy |
|---|---|
| Productive weekday | 14-day deterministic hysteresis (switch/retire) |
| Time-of-day band | 14-day deterministic hysteresis (switch/retire) |
| Momentum | **None** — a current-window fact; must qualify at compose time; after surfacing, a `obs_trend_cooldown_days` (7) cooldown |
| List return | **None** — an event; surfaces within the week, then expires |
| Comeback | Hysteresis as above — a trait earns a grace period and retires after sustained failure, silently |

**The ledger's remaining job (surfacing cadence only):** last-surfaced dates, rundown
weekly cap, copy-rotation state, same-week letter/rundown dedup. Nothing in it can
change a conclusion.

**Ledger hygiene:** keys are **namespaced per Firebase UID**; cleared for that UID on
account deletion; retained but inaccessible after sign-out (rekeyed on next
sign-in). `linkWithCredential` preserves the UID (no migration); the collision path
signs into a *different* UID, which simply starts a fresh cadence ledger — the
conclusions themselves are deterministic, so nothing user-visible is lost. The ledger
stores `obsAlgorithmVersion` + a schema version: **semantic** algorithm changes (band
boundaries, type meaning, replay convention) bump the version and clear surfacing
state; ordinary Remote Config threshold tuning requires nothing — stability is
recomputed deterministically on every evaluation anyway.

#### Output shape

```
ObservationCandidate:            // inspector + tests ONLY
  type, conclusion, evidence     // gate-by-gate pass/fail, margins achieved
QualifiedObservation:            // the only type production surfaces accept
  type         weekday | timeOfDay | momentum | listReturn | comeback
  conclusion   payload (weekday / band / listId / none)
  stableSince  date (from the deterministic replay)

DistributionResult:              // Feature 5's contract
  minutes / buckets              // canonical minutes; histogram views derived
  scopeUsed    list(listId) | globalFallback   // provenance is explicit —
  evidence, confidence                         // a caller can never mistake a
                                               // global fallback for list evidence
```

`timeOfDayDistribution(listId:)` returns `scopeUsed: .globalFallback` when the list
alone is below the evidence floor — the silent-fallback trap is closed by making
provenance part of the result. Reschedule-informed bias (Feature 5) applies only to
records where `rescheduleCount != nil` (Apple-sourced are excluded as *unknown*, not
treated as never-moved).

#### Surfacing rules (ledger-enforced)

- **Rundown priority (canonical one-line rule, owned by Feature 2):** streak
  milestone > anniversary > "crushed yesterday" > memory callback > observation.
  At most **one** Personal-Layer line per rundown; observations additionally capped
  at `obs_rundown_weekly_cap` (2) per week.
- **Letters** pick observation beats by Feature 3's beat priorities; letter usage
  doesn't count against the rundown cap, but the same conclusion never appears in a
  letter and a rundown in the same week (hearing it twice in two days reads as a
  script).
- **The Journal card** ("Mochi has noticed") is ambient and persistent — the current
  qualified set, no rate limits.
- **Lapsed:** the engine isn't consulted (no composing surfaces run); the Journal
  card shows the last qualified set, frozen. **Vacation:** nothing new surfaces
  (letters/rundowns are suspended anyway); the engine still computes on open for the
  Journal.

#### Copy rules

- Every type has its own pool (4–6 lines, round-robin with the don't-repeat-last-N
  guard, per the v0.4 copy-library mechanics), templated with the pet name via the
  Feature 1 helper.
- Register: attention, not measurement — "Nori noticed", "Nori keeps notes", never
  "your average", "78%", "statistics show".
- The night band never implies the schedule is wrong; list-return copy celebrates
  the return and never references the absence that preceded it. Ship test unchanged:
  would this make someone at the floor feel worse?
- Full-sentence String Catalog keys; no concatenation.

#### Dev tool

A `#if DEBUG` **observation inspector** panel added to the existing DevScheduler tab:
every `ObservationCandidate` with gate-by-gate evidence (floors, spread, margins
achieved vs. required), the deterministic-replay timeline (incumbent / challenger /
fail-streak per day — flapping is *visible*), ledger cadence state, and a time-travel
hook reusing the tab's simulated "now". Same rationale as the scheduler inspector,
which found a real bug on first open.

#### Remote Config

New keys, joining `RemoteTuning` under the existing rules (range clamping, console
publication, `consoleKeysMatch` + `everyKeyDecodes` pinning):
`obs_window_days` 42 · `obs_replay_days` 90 · `obs_day_cap` 3 ·
`obs_weekday_min` 15 · `obs_weekday_weeks` 3 · `obs_weekday_share` 0.30 ·
`obs_timeofday_min` 20 · `obs_timeofday_dates` 5 · `obs_timeofday_weeks` 3 ·
`obs_timeofday_share` 0.40 · `obs_margin_ratio` 1.5 ·
`obs_trend_half_min` 10 · `obs_trend_ratio` 1.3 · `obs_trend_min_delta` 0.2 ·
`obs_trend_cooldown_days` 7 · `obs_return_quiet_days` 14 ·
`obs_return_history_min` 5 · `obs_comeback_min` 8 · `obs_comeback_dates` 3 ·
`obs_comeback_tasks` 3 · `obs_comeback_hours` 24 · `obs_comeback_p75_hours` 48 ·
`obs_sticky_days` 14 · `obs_rundown_weekly_cap` 2

*(Threshold changes re-evaluate deterministically on next computation; only semantic
changes touch the version gate — see ledger hygiene.)*

#### Edge-case matrix

| # | Situation | Behavior |
|---|---|---|
| 1 | Fewer completions than any floor | No observations; every surface silently omits — no "not enough data yet" copy |
| 2 | New user, week one | Nothing qualifies by construction; day-1 delight is carried by in-app celebration, not insight |
| 3 | Two weekdays tied or near-tied | Margin gate fails → silence. Ties are exactly the "when unsure" case |
| 4 | One heroic bulk-cleanup morning (20 completions) | Day cap (3) + distinct-date/week gates: a single burst cannot mint "morning person" or a comeback trait |
| 5 | Weekly-Tuesday recurring task dominates Tuesdays | Excluded from the weekday observation (one-off completions only) — the circularity trap |
| 6 | Daily 7am habit dominates time-of-day | Included — *when in the day* the user acts is real behavior; the day cap still limits any single date's weight |
| 7 | User completes tasks in Chicago, then flies to Tokyo | Completions carry their own local context — history is **not** re-bucketed; the Tokyo completions simply accrue with Tokyo context. Apparent behavior never rewrites |
| 8 | Legacy / Apple-sourced rows without stored local context | Interpreted under the current zone, marked derived — the documented fallback; decays out of the window naturally |
| 9 | Completion from the widget, drained next morning | Local context was stamped at completion time in the App Group queue — an overnight drain cannot shift evening behavior into morning |
| 10 | Completions made during vacation | Present in weekday/time-of-day distributions; **fully excluded from momentum** (days *and* their completions) |
| 11 | Window halves touch pre-log vacation/lapse days | Momentum silent — the honest-fallback rule; no normalization without a data source |
| 12 | Recently resubscribed after a lapse | Lapse days ineligible for momentum → no manufactured "rising" trend |
| 13 | Conclusion would change (Tuesday → Thursday) | Deterministic switch: incumbent must fail 14 consecutive daily snapshots while the challenger passes throughout; silent |
| 14 | Incumbent stops qualifying, nothing replaces it | **Retire:** silence after the same 14-snapshot streak — a stale conclusion never lingers for months |
| 15 | Trend ends the day after "More check-offs lately" surfaced | Momentum is a compose-time fact with no incumbency — it simply stops qualifying; cooldown prevents rapid re-surfacing either way |
| 16 | User completes a task in a long-quiet list | List return fires (if history + no-vacation gates pass); surfaces within the week, then expires |
| 17 | Quiet spell was actually a vacation or lapse | List return suppressed — absence wasn't behavior |
| 18 | Same recurring habit slightly late five times | Comeback's task/series diversity gate (≥3 distinct) refuses the trait |
| 19 | Lapsed | Engine not consulted; Journal card frozen at last qualified set |
| 20 | Two devices, same account | Same synced records + interval log + fixed replay convention → identical conclusions; only surfacing cadence is per-device |
| 21 | Sign-out / account switch / deletion | Ledger is per-UID: no inherited cadence, no leaked state; deletion clears the UID's keys |
| 22 | DST transition | Minute-of-day is recorded at completion; at most 1h of skew against 4–8h band views — immaterial |
| 23 | All completions undated | Comeback silent (needs `dueAt`); weekday/time-of-day/momentum unaffected |
| 24 | Contributing list deleted | List-scoped outputs only ever reference surviving `listId`s |
| 25 | Night-shift user (most completions 21:00–05:00) | Night band qualifies like any other; circular math keeps 23:30/00:30 clustered at midnight; copy affirms, never corrects |

#### Instrumentation

- `observation_evaluated` — the denominator: type + `qualified` bool + coarse
  evidence/margin buckets, at most **once per type per user-day**. Without it,
  "rarely shown" can't be told apart from "rarely qualifies" vs. "always loses beat
  priority" vs. "capped".
- `observation_shown` — type + surface + confidence bucket.
- **Neither event ever carries a conclusion payload** (locked).
- Alert-only tripwire on the *qualification* rate: if a type qualifies for almost no
  users after N weeks, thresholds are wrong — flag for a human tuning pass, never
  auto-loosen.
- Acceptance-rate validation for the whole layer lives in Feature 5's
  instrumentation, by design.

#### Test coverage (required)

- **Gate table-drive per type:** below floor / at floor / spread fail (burst
  concentrated in one day or week) / margin fail / all-pass / boundary-exact values.
- **Burst resistance:** 20-completion single morning fails weekday, time-of-day, and
  comeback; the same volume spread over 3+ weeks passes.
- **Local-context model:** Chicago→Tokyo relocation leaves historical conclusions
  bit-identical; fallback rows re-interpret under the current zone; widget-drain
  completions carry completion-time context.
- **Circular math:** 23:30 + 00:30 cluster at midnight, not noon.
- **Momentum:** vacation/lapse days excluded numerator *and* denominator; pre-log
  periods force silence; relative-only jumps below the absolute delta fail.
- **Deterministic replay:** switch and retire transitions; replay from the fixed
  depth is device-order-independent; threshold changes re-evaluate without ledger
  intervention; semantic version bump clears cadence state only.
- **List return:** fires on genuine return; suppressed when the quiet spell overlaps
  vacation/lapse or history floor unmet.
- **Comeback:** diversity gates (dates, tasks/series); p75 catches hidden stalls;
  date-only lateness measured from end of due day.
- **Types:** production surfaces cannot receive an `ObservationCandidate`
  (compile-time); `DistributionResult.scopeUsed` reports fallback correctly;
  `rescheduleCount == nil` excluded from bias (not treated as 0).
- **Ledger:** per-UID isolation across sign-out/switch/deletion; same-week dedup;
  caps; rotation.
- **Determinism:** same records + same parameters + same "now" → identical output;
  no internal clock/timezone/randomness reads.

#### Deferred (not in v1 of this feature)

- Priority-weighted or per-priority insights.
- A full procrastination observation (the v2 signal) — the reschedule counter feeds
  Feature 5's bias only, for now.
- Reschedule *direction* data (a count says a task moved, not that it moved
  morning→evening) — noted for Feature 5's v2.
- Cross-list correlations ("Work crowds out Personal on Thursdays") — richer, riskier
  framing; revisit after acceptance data exists.
- Pre-action neglect observations (the removed list-attention type) — **deliberately
  rejected**, not deferred: an observation about inaction cannot be made safe by
  copy. Any successor must fire on action, as list return does.
- Any negative-pattern surfacing. Deliberately never, absent a philosophy change.

#### Extension — list time-of-day observation (specced Aug 2 2026, unbuilt)

> 🆕 **Added Aug 2 2026** from dogfooding: the Feature 5 `.list`-tier chip already
> tells the user "{list} things usually get done in the evening" at the moment of
> scheduling. The same trait deserves an ambient home in the Journal. Decisions
> locked in review: **noticed card only · divergence-gated · Journal-only first.**

**What it is.** A sixth observation type, `listTimeOfDay` — a trait (deterministic
14-day replay hysteresis like weekday / time-of-day / comeback) concluding one
**(list, band)** pair: "this list's things tend to happen in this band."

**Why it is not a moment or a letter beat (v1).** The conclusion is derived and can
strengthen, shift bands, or evaporate — freezing it into the timeline would violate
record-vs-derive. It renders on the live "{name} has noticed" card, which already
retires stale lines by construction. Letters and rundowns are explicitly out of
scope for v1; widen only after the card reads well in practice. It also never
becomes an editor chip — Feature 5 already owns that surface.

**Evidence & gates** (new `obs_list_tod_*` Remote Config keys; shared gates reuse
the existing keys):

| Gate | Value |
|---|---|
| Evidence floor | ≥ `obs_list_tod_min` (15) day-capped completions in the list within the 42-day window |
| Spread | ≥ `obs_list_tod_dates` (5) distinct dates across ≥ `obs_list_tod_weeks` (3) distinct weeks; per-(list, day) cap of `obs_day_cap` (3) |
| Concentration guard | ≥ 3 distinct task/series identities and no identity > 0.40 of the capped count — one daily habit can't speak for a whole list (mirrors Feature 5's list scope; pinned in code v1, promotable to RC later) |
| Margin | top band share ≥ `obs_list_tod_share` (0.40) **and** ≥ `obs_margin_ratio` (1.5×) runner-up |
| **Divergence** | qualifies **only when the list's band differs from the currently qualified global time-of-day band, or no global band is qualified**. A list matching the global rhythm is silence — the global line already says it. Replayed like every other gate, so a global-band switch or retirement re-decides the list line deterministically |

**One incumbent overall.** At most one (list, band) incumbent at a time; when
several lists qualify, the strongest wins (highest band share, ties by evidence
count, then stable list id). Switch and retire under the standard 14-day rule.
Mochi lists only — Apple Reminders rows are structurally excluded, as in Feature 5.
A deleted list disqualifies immediately (a noticed line naming nothing is
pointless); a renamed list renders live, since nothing is frozen.

**Card behavior.** Lowest trait priority in the qualified order — it fills the last
of the card's 3 slots, never displaces a global trait. Copy rotation, per-day
phrasing stability, and lapse peek behavior all inherit from the card.

**Copy** (two new pools; qualitative, no counts, third person, night affirming —
first-person "Hey! Mochi here!" register deliberately rejected in review):

`obs-list-tod` — {band} ∈ "in the morning" / "in the afternoon" / "in the evening":
- `{list} things usually happen {band}. {name} noticed.`
- `{list} has its own hour. {name} keeps notes on these things.`
- `{list} tends to move {band}. {name} has seen it enough to be sure.`
- `{name} noticed {list} gets its turn {band}.`

`obs-list-night` — its own pool so the affirming stance is structural:
- `{list} gets its attention after dark, and that counts just the same. {name} noticed.`
- `The late hours are when {list} moves. {name} thinks that's a fine time for it.`
- `{name} noticed the quiet hours are when {list} gets shorter. No notes, just admiration.`
- `Night is when {list} moves. {name} keeps you company either way.`

**Bookkeeping.** RC pin moves 84 → 88 (4 new keys; console publish user-owned, per
the standing follow-up). Telemetry reuses `observation_evaluated` /
`observation_shown type=listTimeOfDay surface=journal` — never the list name.
`Mochi-journal.md` §5 gains the type only once it ships (that doc records shipped
code).

**Test coverage (required).** Divergence gate flips with the global incumbent under
replay; concentration guard (one daily habit fails, three identities pass);
burst resistance; strongest-list tie-breaking is deterministic; deleted list
retires immediately; rename renders live; determinism and
current-zone-independence like every other type.

### Feature 5 — Suggested times

> 🆕 **v0.7 — RESOLVED** *(revised after review: **runner-up margin + peak-date
> spread gates** make "bimodal means silence" true by construction (the 0.35 share
> alone did not); evidence qualifies on **raw day-capped counts** — reschedule
> weights shape a qualified peak, never manufacture qualification; series scope
> strengthened (8 completions / 5 dates / 3 in-peak) with **highest-qualifying-scope**
> precedence and a list-concentration guard (one daily habit can't speak for a whole
> list); rounding tie/ordering rules + a **30-minute lead-time guard**; **re-time
> copy fixed for consent accuracy** — it changes the task's *due time*, not "the
> reminder" — with the plan-vs-deadline inference limitation named; session-frozen
> chip lifecycle; dismissal ledger keyed by trigger + rounded displayed proposal,
> task id preallocated for unsaved tasks; **save-based terminal outcome
> definitions** (cancel = no outcome; dismissed-then-matched = matched); the
> validator claim narrowed — this validates insight *actionability*, not the
> layer's emotional value — with cohort stratification and a downstream retention
> signal).* The insight that acts: one editor chip from when the user actually
> completes things.

#### Intent

An insight the user reads once is decoration; an insight that makes tomorrow's
reminder land at the right moment compounds forever. The suggestion chip is the
smallest possible expression of "Mochi knows me": one line, one tap, invisible when
unsure. Everything hard here — evidence, provenance, honesty about what the data
supports — was already built in Feature 4; this feature's job is to consume those
contracts without cheating them.

#### Locked decisions

- **Editor-only, one chip, one tap, never modal, never a prompt, never auto-set.**
  The chip appears inline in the task editor when its gates pass and is otherwise
  absent — no empty placeholder, no layout jump, no badge. Accepting sets the time
  exactly as a manual pick would (fully editable after); nothing ever changes
  without the tap.
- **Two triggers, both in the editor:**
  1. **New time** — date set, no time chosen, gates pass → "Nori suggests 10:00 am."
  2. **Re-time** — an existing recurring task *with* a time whose series completions
     persistently land far from it → **"This usually gets done around 8:00 pm.
     Change its time?"** The copy says what the tap does: it changes the task's
     **due time** — overdue onset, stress accrual, promise scheduling, and future
     occurrences — not merely "the reminder." Consent must be accurate.
- **Re-time's honest inference limitation, named:** a task scheduled at 9:00 am but
  completed at 8:00 pm may have a *genuine* 9:00 am deadline — completion data
  cannot distinguish an unrealistic plan from repeated lateness against a real one.
  The editor-only, opt-in posture is what makes this acceptable; the copy must
  never imply Mochi knows the later time is objectively better.
- **Suggestions come only from the engine's `DistributionResult` — and the reason
  copy must match `scopeUsed`.** Scope precedence is **highest *qualifying* scope:
  series, else list, else global** — a scope wins only by passing *all* of its own
  gates, never by merely having rows. A global-fallback suggestion may never be
  *explained* as list- or task-specific: series → "This one usually happens around
  8pm." · list → "Personal things usually get done in the evening." · global →
  "You usually finish things in the evening."
- **When unsure, no chip — and "bimodal means silence" is structural.** Evidence
  qualifies on **raw, day-capped completion counts** (weights never help
  qualification): `suggest_min_evidence` (15) in-scope completions across ≥
  `suggest_min_dates` (5) distinct dates. The peak then passes three gates: share ≥
  `suggest_peak_share` (0.35) within ± `suggest_peak_window_min` (90) of the peak
  center; **the primary window contains completions from ≥ `suggest_peak_dates`
  (3) distinct dates** (a cluster minted on two odd days fails even if the global
  date floor passes); and **primary share exceeds the strongest non-overlapping
  runner-up window by ≥ `suggest_runner_up_margin` (0.10)** — runner-up = the best
  ±90-minute window whose center sits ≥ 3 circular hours from the primary center,
  found by scanning half-hour candidate centers (deterministic). Six-at-9am /
  six-at-6pm is two real patterns and produces silence, not a tiebreak.
- **Friendly times only, with pinned rounding rules.** The circular peak (kernel
  over canonical minutes, per Feature 4) rounds to the **nearest half hour**
  ("10:00", never "10:23" — false precision reads as surveillance); exact
  quarter-hour ties round to the **earlier** half hour; rounding never crosses the
  task's date boundary (23:45 → 23:30, never the next day's 00:00). **All
  guardrails evaluate the *rounded* time.** Re-time's 3h mismatch is measured
  against the **unrounded** peak; only the proposal is rounded.
- **Guardrail silences (never clamp, never fabricate):** no suggestion whose
  rounded time falls inside the bedtime window; for today-due tasks the rounded
  time must be ≥ `suggest_min_lead_min` (30) in the future — a 10:00 chip at 9:58
  is technically future and practically useless, and it is silenced, never moved
  later; no chip while **lapsed** (everything that makes it Mochi is asleep);
  chips allowed during **vacation** (the app stays fully usable; the time matters
  after the trip). In every blocked case the chip is simply absent — the feature
  never explains itself.
- **List scope can't be one habit wearing a list costume.** List evidence
  additionally requires ≥ `suggest_list_min_series` (3) distinct task/series
  identities, and no single series may contribute > `suggest_list_series_share`
  (0.40) of the list's capped effective weight — else fall through to global. The
  provenance principle applied to data breadth: the evidence must support the
  *width* of the claim ("Personal things…"), not just its direction.
- **Apple-sourced tasks: no chip in v1.** EventKit is their home store, so
  accepting a suggestion would require writing the due time back to EventKit — and
  Apple Reminders' notification behavior hinges on alarm semantics, not just
  `dueDateComponents`, which deserves its own decision rather than a side effect
  here. Their completions still feed the distributions; only the chip is withheld.
  (Deferred, with the alarm question named.)
- **The reschedule bias, concretely (Feature 4's contract consumed):** completions
  whose `rescheduleCount ≥ 1` get a modest extra weight **in the peak calculation
  of an already-qualified distribution** — `1 + min(rescheduleCount, 3) ×
  suggest_reschedule_weight` (0.25, max 1.75×) — because a task the user kept
  moving is extra-informative about when things *actually* happen.
  `rescheduleCount == nil` (Apple) means weight 1, **unknown, never "known
  unmoved"**. Direction-aware bias stays deferred (Feature 4's noted v2).
- **Dismissal is once-until-changed, keyed by trigger.** Ledger key: UID + trigger
  type (newTime / reTime) + task id (new-time) or series id (re-time) + the
  **rounded displayed minute**. Re-arm compares rounded displayed proposals — an
  internal peak drift from 10:05 to 10:20 that still displays "10:00" changed
  nothing for the user; re-arm requires ≥ `suggest_dismiss_rearm_min` (60)
  circular minutes of *displayed* change. Dismissing a new-time chip never
  suppresses a later re-time offer that happens to propose the same clock time.
  For a not-yet-saved task, the task id is **preallocated when the editor opens**
  so a dismissal survives the save. Rides the shared surfacing ledger —
  device-local, cadence-only, honestly per-device.
- **Session-frozen chip lifecycle.** At most one presentation per trigger per
  editor session; once shown, its candidate time and provenance are **frozen for
  that session** — the chip never flickers or regenerates as the user toggles
  fields. Manual changes can satisfy or remove it; acceptance, dismissal, or a
  manual match ends its lifecycle; reopening the editor is a new session, subject
  to the dismissal ledger.
- **Deterministic end to end.** The suggestion is a pure function of (scope
  distributions, task, parameters, calendar/zone as arguments) — same chip on
  every device, same inputs → same time, no hidden clock reads.

#### Chip UI

- **Placement:** an inline row directly under the date/time controls in
  `TaskEditorView`, present only when a trigger's gates pass.
- **Anatomy:** SF Symbol clock glyph · chip label "Nori suggests 10:00 am" · the
  scope-matched reason as a one-line subtext · a small dismiss affordance. No
  percentages, no evidence talk, no emoji (copy-style rule).
- **Tap:** sets `hasTime` + the time, chip transitions to a quiet confirmed state
  ("10:00 am set"), everything remains editable; saving proceeds through the normal
  editor path (promise re-lay on save is the existing trigger — no new scheduler
  path).
- **Dismiss:** removes the chip per the trigger-keyed once-until-changed rule; no
  confirmation, no "are you sure".
- **Accessibility:** the chip is a button — "Set time to 10:00 AM. Nori's
  suggestion: you usually finish things in the evening." Dismiss is labeled
  "Dismiss suggestion". Dynamic Type wraps the reason line rather than truncating
  the time.

#### Re-time trigger detail

- Eligibility: recurring, `source == mochi`, has a due time, and the **series
  passes its own scope gates**: ≥ `suggest_series_min` (**8**) timed completions
  across ≥ `suggest_series_dates` (5) distinct dates with ≥ 3 dates inside the
  peak window, the runner-up margin, and circular distance between the *unrounded*
  series peak and the scheduled time ≥ `suggest_retime_mismatch_hours` (3). Eight
  across five dates is slow-but-honest for a weekly series and no cold-start
  burden for a daily one; five completions were too thin a basis for proposing a
  due-time change (two in-window completions could carry the gate).
- The offer proposes the series' own peak (friendly-rounded), applies to the
  series going forward (the normal recurring-edit semantics), and re-lays on save
  like any editor change.
- Dismissing follows the trigger-keyed once-until-changed rule on the rounded
  proposal.
- Never offered on one-off tasks — **there is no future series to change** (and no
  series is ever inferred by matching titles; titles are user content, not
  identity). At most one presentation per editor session, frozen per the lifecycle
  rule.

#### Remote Config

`suggest_min_evidence` 15 · `suggest_min_dates` 5 · `suggest_peak_share` 0.35 ·
`suggest_peak_window_min` 90 · `suggest_peak_dates` 3 ·
`suggest_runner_up_margin` 0.10 · `suggest_series_min` 8 ·
`suggest_series_dates` 5 · `suggest_list_min_series` 3 ·
`suggest_list_series_share` 0.40 · `suggest_retime_mismatch_hours` 3 ·
`suggest_min_lead_min` 30 · `suggest_dismiss_rearm_min` 60 ·
`suggest_reschedule_weight` 0.25 — joining `RemoteTuning` under the standard rules.

#### Edge-case matrix

| # | Situation | Behavior |
|---|---|---|
| 1 | Cold start / evidence floor unmet | No chip, silently — the feature is simply absent |
| 2 | Bimodal pattern (6 at 9am, 6 at 6pm, 3 scattered) | Runner-up margin fails (both windows ~0.40) → silence — two real patterns, no tiebreak |
| 3 | Peak cluster from only 2 distinct dates, general date floor met | Peak-date spread gate (≥ 3) fails → silence |
| 4 | List evidence thin, global rich | `scopeUsed: globalFallback` → chip shows with the *global* reason copy — provenance can't be misstated by construction |
| 5 | List dominated by one daily habit (> 40% of capped weight) | List scope disqualified → global fallback with global copy — one series can't speak for a list |
| 6 | Series with 6 timed completions | Below the series floor (8) → series scope doesn't qualify; list/global may still serve a new-time chip; no re-time |
| 7 | Peak rounds into the bedtime window | No chip — never clamp to a fabricated time |
| 8 | Task due today, chip would show 10:00 at 9:58 | Lead-time guard (30 min on the *rounded* time) → silence, never moved later |
| 9 | 23:45 peak | Rounds to 23:30 — the equally near 00:00 crosses the date boundary; ties otherwise round earlier |
| 10 | Apple-sourced task | No chip (EventKit write-back deferred with the alarm-semantics question); its completions still feed distributions |
| 11 | Lapsed | No chips anywhere (editing remains possible; Mochi is asleep) |
| 12 | Vacation | Chips work normally — the app stays fully usable |
| 13 | User taps the chip, then adjusts the time, then saves | Outcome: *adjusted* |
| 14 | User never taps but saves a manual time within ±30 circular minutes | Outcome: *matched* — implicit agreement (with a known round-time chance component; see instrumentation) |
| 15 | User dismisses, then manually sets the suggested time and saves | Outcome: *matched* — the save-time state outranks the earlier gesture |
| 16 | User cancels the editor without saving | **No outcome recorded** — an abandoned session is not evidence against the suggestion |
| 17 | Dismissed at "10:00"; internal peak drifts 10:05 → 10:20 | Still hidden — the displayed proposal never changed; a ≥ 60-minute displayed shift re-arms |
| 18 | New-time dismissed at 10:00; later re-time proposes 10:00 | Re-time still offered — dismissal is keyed by trigger type |
| 19 | Dismissal on a never-saved task | Survives the save — the task id was preallocated at editor open |
| 20 | Recurring task completed ~20:00 nightly, scheduled 09:00 | Re-time fires in the editor (unrounded-peak mismatch ≥ 3h, series gates met), copy: "Change its time?" |
| 21 | One-off task completed far from its scheduled time | No re-time — there is no future series to change; new-time suggestions still serve one-offs via list/global |
| 22 | Timezone travel | Distributions are canonical local minutes (Feature 4 model); the suggestion renders in the current zone passed as a parameter — no re-bucketing drift |
| 23 | Two devices, one dismissed the chip | The other may still show it (device-local ledger) — accepted, documented, same class as Feature 2 |
| 24 | `rescheduleCount == nil` completions in scope | Weight 1 in peak shaping; **never counted differently for qualification** (qualification is raw counts regardless) |

#### Instrumentation — the layer's actionability validator

What this feature validates, precisely: **whether behavioral insights are
actionable** — not whether letters, callbacks, or the Journal are emotionally
valuable. A dead global fallback means "remove or redesign global fallback," not
"the relationship layer failed."

- `suggestion_evaluated` — the denominator (once per editor session where a
  trigger's preconditions held): trigger type + qualified bool + coarse blocked
  reason (evidence / peak share / runner-up / peak dates / bedtime / lead time /
  apple / lapsed / dismissed).
- `suggestion_shown`: trigger type + scope tier (series / list / global) + evidence
  bucket + recurring-vs-one-off.
- `suggestion_outcome` — **classified once, at editor save** (cancel without save =
  no outcome): **accepted** (tapped, saved the exact proposed time) · **adjusted**
  (tapped, changed, saved) · **matched** (never tapped; saved a manual time within
  ±30 circular minutes) · **dismissed** (dismissed and did not later match) ·
  **ignored** (saved with none of the above). Precedence at save: tapped state >
  matched state > dismissed > ignored — a dismiss followed by manually choosing the
  suggested time is *matched*, the more informative signal.
- **Signal weights, stated:** *accepted* is the primary validator; *matched* is
  supporting evidence (round times like 9:00/10:00 match by chance — always report
  components separately, never only the combined rate); *adjusted* is partial
  influence; *dismissed*/*ignored* are negative signals of different strength.
- **Stratification, because populations differ:** by trigger type, scope tier,
  evidence bucket, and recurring-vs-one-off. Scope comparisons are valid only
  within comparable cohorts (new-time on recurring tasks: series vs. list vs.
  global). **Re-time has no global control group** — evaluate it on absolute
  acceptance plus the retention signal below.
- **Downstream retention (coarse, device-computed — the "did it actually help"
  signal):** whether an accepted time survived unchanged through the next
  occurrence; whether that occurrence completed within a coarse window of its
  scheduled time; whether a re-time was reversed in the next edit. Reported as
  trigger type + scope + coarse success bucket only — no titles, ids, times, or
  lateness values leave the device. Re-time especially needs this: a user may tap
  experimentally and discover the due-time semantics were not what they wanted.
- **No payloads**: no times, no list ids, no titles — the one rule, everywhere.
  Alert-only, human-reviewed, as always.

#### Test coverage (required)

- **Gates table-drive:** raw-count qualification (weights excluded), distinct
  dates, day-cap, peak share, **peak-date spread**, **runner-up margin with the
  3h-separated window scan**, boundary-exact values; silence on every failure;
  the bimodal 6/6/3 case explicitly.
- **Circular math:** peak detection across midnight; rounding (nearest half hour,
  quarter-ties earlier, 23:45 → 23:30 boundary rule); re-time distance on the
  unrounded peak (21:00 vs 09:00 wrap).
- **Scope:** highest-*qualifying*-scope precedence (a rich-but-unqualified series
  loses to a qualified list/global); list concentration guard (identity floor +
  40% share) falling through to global.
- **Provenance copy:** scope tier ↔ reason copy pinned by table-driven mapping; a
  `globalFallback` result can never render series/list phrasing.
- **Guardrails:** bedtime window, lead-time guard at 30 minutes on the rounded
  time, Apple-source, lapsed, vacation-open each gate correctly — always to
  silence, never to a shifted time.
- **Reschedule weighting:** formula and 1.75× cap in peak shaping only; nil = 1;
  qualification counts unchanged by weights.
- **Dismissal ledger:** trigger-keyed isolation (new-time dismissal doesn't block
  re-time); rounded-displayed-proposal comparison (10:05 → 10:20 no re-arm; ≥ 60
  displayed minutes re-arms); preallocated-id survival across first save;
  round-trip.
- **Session lifecycle:** one presentation per trigger per session; frozen
  candidate; no regeneration on field toggles; reopening re-evaluates.
- **Re-time:** series gates (8 / 5 dates / 3 in-peak), mismatch threshold,
  series-forward application, one-off exclusion, no title-based series inference.
- **Outcome classification:** all five outcomes + the no-outcome cancel path from
  simulated editor flows; dismissed-then-matched resolves to matched; ±30-minute
  circular matched window.
- **Determinism:** same distributions + task + parameters → same suggestion on any
  device; no internal clock/zone reads.

#### Deferred (not in v1 of this feature)

- **EventKit time write-back** for Apple-sourced tasks — requires deciding alarm
  semantics (a Reminders due time without an alarm notifies differently), not just
  `dueDateComponents`.
- Direction-aware reschedule bias (Feature 4's noted v2 — needs morning→evening
  move data, not a count).
- Suggestion surfaces beyond the editor (rundown "want me to time these?" — a
  different consent posture; revisit only with strong validator data).
- Snooze-menu target tuning from the same distributions ("tonight" = *their*
  evening) — cute, cheap, after the validator proves the model.
- Per-priority or day-of-week-conditional time suggestions.

### Feature 6 — Journal tab

> 🆕 **v0.7 — RESOLVED** *(revised after review: **one unified story timeline**
> replaces the archive-plus-timeline split (the hero is a presentation state, not
> a copy); the philosophy restated as **record vs. grade** — and **coins removed**
> from the footer (currency state, not a record); an **exhaustive natural-ID
> table** whose ids identify *events*, not categories (repeat 30-day streaks and
> same-date vacation returns no longer collide); **deterministic snapshot
> payloads** derived from immutable event facts, never live lookups at write time;
> the adoption moment made **atomic** (batched with `adoptedOn`, with
> deterministic synthesis as fallback) and legacy-safe copy that never implies the
> current name was used then; the young-state promise corrected for Feature 3's
> gating; lapse freezing pinned as **`effectiveNow = lapseStartedAt`**; the
> best-streak backfill **dropped** (adoption only); timeline calendar semantics
> pinned to stored dates and zones; viewport-based impression definition;
> anti-churn labeled correlation, not proof).* The container, shipped last — and
> deliberately *only* a container: **no new engines, no new gates, zero Remote
> Config keys**. Fourth tab (**Home · Tasks · Journal · You**). The You tab sheds
> Stats and returns to pure settings.

#### Intent

A wavering subscriber at renewal scrolls three months of letters and moments — the
accumulated relationship made visible. This is the single strongest anti-churn
surface available to the app, and it is built entirely from artifacts the other
five features already produce. The Journal's discipline is curatorial:
**everything in the narrative layer either happened (letters, moments) or
qualified (observations); nothing grades the user; the data footer records
activity without judging it.** Record vs. grade is the line — not measurement vs.
non-measurement.

#### Locked decisions

- **Named "Journal," statically.** "Diary" reads childhood-secret and localizes
  worse. The **tab label is the static word "Journal"** with an SF Symbol book
  glyph (`PlaceholderArtIcon` convention until commissioned art lands, roadmap #6)
  — tab bars never carry user content (a 16-grapheme pet name in a tab label is
  the exact compact-surface failure Feature 1 cataloged). The *screen* header is
  possessive and alive — "Nori's Journal" — as a **full localized format string**
  (never English possessive concatenation; possessive morphology is per-locale,
  the Feature 1 rule extended), with the compact fallback rules and the live pet
  name (headers update on rename; artifacts inside keep their snapshots). The
  observation card title likewise uses the live name: **"Nori has noticed."**
- **One primary feed — the unified story timeline.** Content order: **newest
  unread letter as hero → story timeline (letters and moments interleaved,
  newest first, month-grouped) → observation card → data footer.** The hero is a
  **presentation state of a timeline letter, never a second copy**: while
  promoted it is excluded from the rows below; once read it returns to its
  chronological row. Multiple unread letters: newest unread is the hero, older
  unread rows carry an unread trait, and the Home envelope clears only when all
  are read (synced `readAt`). Feature 3's `LetterArchiveView` components are
  reused as the letter row/detail implementations (the promised navigation-only
  handoff); a dedicated "All letters" filter is a later affordance, not a second
  embedded archive.
- **Moments are synced, deterministic-id, create-only documents — from day one.**
  This deliberately overrides the skeleton's "local store first, sync later": the
  Journal's entire value is *the* accumulated record, a per-device record
  undermines it on the second device, letters already forced the synced pattern,
  and natural-key create-only writes make concurrent creation idempotent. **The
  id must identify the event, never merely its category** — exhaustive v1 table:

  | Type | Natural identity |
  |---|---|
  | Adoption | `adoption-{adoptedOn}` |
  | Anniversary | `anniversary-{tier}-{occurredOn}` |
  | Streak milestone | `streak-milestone-{count}-{occurredOn}` (a broken-and-rebuilt 30-day streak is a *new* moment, not a suppressed duplicate) |
  | Vacation return | `vacation-return-{intervalId}` (end-reenter-end on one date = two intervals = two moments) |
  | List return | `list-return-{listId}-{sourceEventId}` |

- **Deterministic payloads, not just deterministic ids.** Create-only picks one
  winner among racing writers — so **every writer deriving the same id must
  derive the same canonical payload, from immutable event facts**. Snapshot
  inputs travel *with the qualifying event* (a list-return event carries the list
  name as of the event; the winner never looks up the current name at write
  time). Moment document:

  ```
  type, occurredOn (date-only)
  renderedTextSnapshot, accessibilityTextSnapshot
  petNameSnapshot?, subjectNameSnapshot?      // as of the event
  localeIdentifier, copyDeckVersion           // provenance
  sourceEventId, schemaVersion, createdAt
  ```

  Not every field applies to every type; what matters is that snapshots come from
  the event. Snapshotted prose keeps its **original language after a locale
  change** — the postcard rule, documented deliberately.
- **Moment producers (exhaustive, v1):** adoption, streak milestones,
  anniversaries (including vacation-deferred acknowledgments, recorded on their
  *true* date), vacation returns, and Feature 4 list-return events. Letters are
  **interleaved by reference**, never duplicated into moments.
- **The adoption moment is atomic — the non-emptiness guarantee is structural.**
  `adoptedOn` and the adoption moment are written **in the same Firestore batch**
  at onboarding/migration; as defense, the Journal **deterministically
  synthesizes** the adoption row from `adoptedOn` whenever the document is absent
  while enqueueing the idempotent write. **Legacy-safe copy:** a backfilled
  adoption date is known but the pet's name *on that date* is not — backfilled
  moments read **"The day your story began"** (no name implied); new adoptions
  snapshot the name actually captured at onboarding.
- **No guessed history — adoption is the only backfill.** The earlier best-streak
  backfill idea is dropped: it conflated a *milestone* (an event) with a *record*
  (a superlative that goes stale — "your best streak was 23" becomes false at
  24, and immutable text must never become false). Historical milestone dates are
  unknown; unknown-date history is never invented (the Feature 2 doctrine).
- **The data footer records; it never grades — and coins are out.** It keeps the
  week strip, the 4-week trend, done-this-week, and best streak: activity,
  recorded without judgment. **The on-time percentage is removed** (a rate is a
  grade), the ungated "busiest on Tuesdays" caption is removed —
  `StatsViewModel.busiestWeekday` has **no evidence gating**, exactly the
  confident-wrong-conclusion Feature 4 exists to prevent; the gated observation
  card replaces it or nothing does — and **coins are removed from the Journal**:
  a spendable balance is currency state, not a historical record (it lives on
  Home; no "lifetime earned" stat is invented just to justify a Journal row).
- **Never an empty chart, and never an empty Journal.** The atomic adoption
  moment guarantees content from day one; the "empty state" is really the *young*
  state: the adoption moment plus one forward-looking line — **"After your first
  full week together, Sunday letters will collect here."** (Accurate to Feature
  3's gating: a day-one user does *not* get the upcoming Sunday's letter.) The
  data footer renders only once the strip has ≥ 1 completion; the observation
  card only with a non-empty qualified set — absent sections are omitted, never
  placeholdered (the silence rule, applied to layout).
- **Lapsed: readable, frozen at a pinned cutoff, zero come-back copy.** The tab
  remains; everything renders; nothing new composes. **"Frozen" is defined:
  Journal derivations evaluate with `effectiveNow = lapseStartedAt`** (from the
  Feature 4 interval log) — the week strip, trend, done-this-week, best-streak
  display, and observation set stop moving, rather than decaying toward zero as
  calendar windows slide, even though existing tasks remain completable during
  lapse. On reactivation the data footer resumes **live over full retained
  history, including work completed during the lapse** — relational artifacts
  never backfill, but factual checklist history is never discarded. Reading your
  pet's old letters while lapsed remains the best winback screen possible
  *precisely because* it contains no winback copy. **Vacation:** fully accessible,
  quiet; the vacation-return moment is written at re-entry, not during.
- **Architecture per the house pattern:** `Journal/` module with
  `JournalView` / `JournalViewModel` / `JournalBehavior` and a `JournalRouter`,
  slotting into `MainTabView` between Tasks and You. The Stats module retires:
  week-strip/trend derivations move over largely intact; on-time and
  busiest-weekday derivations are deleted with this spec as the recorded reason.
  Letter-notification taps and the Home envelope route into the Journal's letter
  view via the existing stable ids. **Security rules** on moments validate more
  than create-only: allowed type enum, schema version, required fields, and an
  id prefix consistent with the declared type (create-only prevents edits, not
  fabricated or malformed documents). Account deletion removes letters + moments
  through the same privileged subtree-deletion path as everything else.

#### Timeline composition

A merge, not an engine — with **pinned calendar semantics**: a letter's timeline
date is the calendar date of its `periodEndExclusive` **in the timezone stored on
that letter**; a moment's is its `occurredOn`. Month grouping uses these stored
dates, **never the device's current timezone** — travel cannot move old artifacts
between months. Sort newest-first; same-day ties order letters first (the richer
artifact), then moments by natural-key id — deterministic on every device.
Implementation note: letters and moments are separate collections, so each month
page is **two bounded queries + the pure merge**; there is no cross-collection
cursor.

#### Empty / young / rich states

| State | Condition | Renders |
|---|---|---|
| **Young** | adoption moment only | Adoption moment + the forward-looking line; no charts, no observation card |
| **Growing** | any completions / letters / moments | Whatever exists, in content order; absent sections omitted |
| **Rich** | months of history | Full order incl. data footer; month grouping carries the scroll |

#### Instrumentation

- `journal_opened`: source (tab / Home envelope / letter notification).
- Section impressions (timeline / observations / data), **defined by viewport,
  not construction**: logged once per Journal session when roughly half the
  section becomes visible — lazy or prefetched content must not count as "earned
  the scroll."
- **No payloads** — the composing features already report their own creation
  events.
- **Anti-churn is correlation, not proof** (the Feature 3 doctrine): Journal
  readers were likely more engaged *before* opening it. The analysis over
  `journal_opened` and subscription events uses within-user timing or matched
  engagement cohorts, informs human judgment, and never claims causation. No new
  event needed — noted so nobody adds one.

#### Edge-case matrix

| # | Situation | Behavior |
|---|---|---|
| 1 | Day-one Journal | Adoption moment (atomic with `adoptedOn`) + forward-looking line; no empty charts, no placeholder cards |
| 2 | Adoption moment missing despite `adoptedOn` (batch interrupted, legacy edge) | Journal synthesizes the row deterministically and enqueues the idempotent write — non-emptiness holds |
| 3 | Two devices observe the same milestone | Same natural id **and same canonical payload** (derived from event facts) → one moment, content-identical regardless of winner |
| 4 | Streak reaches 30, breaks, reaches 30 again | Two moments — `streak-milestone-30-{date}` identifies the event, not the category |
| 5 | Vacation ended, re-entered, ended on the same date | Two moments — keyed by `intervalId`, not date |
| 6 | Newest letter unread | Hero treatment; that letter is excluded from the rows below; returns to its chronological row once read |
| 7 | Multiple unread letters | Newest is hero; older carry an unread trait in the timeline; Home envelope clears only when all are read |
| 8 | Legacy user at feature launch | Adoption backfilled with the neutral "The day your story began" (never implies the current name was used then); **no** best-streak or milestone history invented |
| 9 | List-return moment, list later deleted/renamed | Renders its event-time name snapshot unchanged — the timeline never rewrites |
| 10 | Device locale changes | Old moments and letters keep their original language (snapshotted prose, `localeIdentifier` recorded) — the postcard rule |
| 11 | Pet renamed | Screen header and observation-card title update live; artifacts keep their snapshots |
| 12 | Observation set becomes empty | Card disappears entirely; no "nothing yet" |
| 13 | Zero completions in the strip window | Data footer omitted |
| 14 | Lapsed | Tab remains; derivations frozen at `effectiveNow = lapseStartedAt` (no live drift, no decay-to-zero); zero come-back copy |
| 15 | Reactivation after lapse | Data footer resumes live over full retained history incl. lapse-period completions; artifacts never backfill |
| 16 | Timezone travel | Timeline dates come from stored letter zones and date-only `occurredOn` — artifacts never migrate between months |
| 17 | Long pet name | Tab label is static "Journal"; header and card title follow Feature 1 compact rules |
| 18 | Tab rollout | The You "Stats" and interim "Letters" rows retire atomically with the tab's introduction; letter routes survive via stable ids |
| 19 | Malformed or fabricated moment write | Rejected by rules: type enum, schema version, required fields, id-prefix-vs-type consistency |
| 20 | Account deletion | Letters + moments removed via the privileged subtree-deletion path |
| 21 | DEBUG builds | The DevScheduler tab in You is unaffected |

#### Test coverage (required)

- **Timeline merge:** stored-zone/date sort keys (travel moves nothing), month
  grouping, same-day tie rule, two-query month pagination, determinism across
  devices.
- **Hero lifecycle:** promotion excludes the letter from rows; read returns it;
  multi-unread trait handling; envelope clears only at zero unread.
- **Moment identity:** the full natural-ID table incl. repeat-streak and
  same-date-vacation cases; concurrent double-write resolves to one
  content-identical document (payload derived from event facts, asserted).
- **Adoption atomicity:** batch write; synthesis fallback renders and enqueues;
  idempotent on repair; legacy copy contains no pet name.
- **Backfill:** adoption only; nothing else invented; idempotent on second run.
- **Snapshots:** list-return renders after list deletion/rename; locale change
  leaves old prose untouched; header/card title update on rename while artifacts
  don't.
- **States:** young / growing / rich; absent-section omission; **no coins, no
  on-time percentage, no ungated busiest-weekday anywhere in the Journal**
  (assert on the view model's output surface).
- **Lapse freeze:** derivations pinned at `lapseStartedAt` (strip/trend/counts/
  observation set immobile while tasks complete); reactivation resumes live incl.
  lapse-period history.
- **Security rules:** create-only + type enum + schema + required fields + id
  prefix; update attempts rejected.
- **Navigation migration:** Stats and Letters rows gone from You; tab present;
  letter notification and Home envelope route correctly.
- **Accessibility:** timeline is a proper list; the hero letter announces as
  unread; **noninteractive moment rows expose no button traits**; section headers
  are landmarks.

#### Deferred (not in v1 of this feature)

- Moment detail views beyond the timeline row (tapping a letter opens the letter;
  tapping a moment does nothing yet).
- An "All letters" filter over the unified timeline (the reused letter components
  make it cheap when wanted).
- Sharing moments (letters own the share surface; a shareable "one year together"
  card is an obvious v2).
- A lifetime-coins-earned record (only if the counter is ever genuinely
  persisted — never invented for a statistic).
- Search or a year-in-review view over the archive (waits for the year-in-review
  letter, Feature 3's noted v2).
- Any Journal-only notification. The Journal is a destination, never a voice.

---

## The discovery batch

> 🆕 **v0.8.** The four items taken up after the Personal Layer shipped, plus the one
> that was tabled during discovery. TestFlight was deliberately deferred to allow this
> batch. Original order was five items; the calendar was item 4 and is now tabled, so
> Editor layout took its number.
>
> **Naming warning.** "Feature 4" is overloaded. In *The Personal Layer* it means
> **Feature 4, Mochi's observations** (`Observations/`), which is shipped and live.
> The discovery batch's former item 4 was the calendar. Refer to that one as "the
> calendar layer", never by number.
>
> Long-form working notes for every item below are archived under
> `ProjectDocs/build-notes/`.

**Batch order and state:**

| # | Item | State |
|---|---|---|
| 1 | Best Hours & Day by day | ✅ Built July 27 2026, comp-approved |
| 2 | Suggestion reach (weekday fallback · row badge · push counting) | ✅ Built July 27 2026, comp-approved |
| 3 | Effort size | ✅ Built July 27 2026, comp-approved |
| 4 | Editor layout (ghost pill) | ⬜ Design locked, not built, no comp |
| — | Calendar access | ⛔ Tabled July 25 2026 (not cancelled) |

---

### Best Hours & Day by day

Two cards on **Streaks & stats** (`You/Stats/`) replacing the retired "Your rhythm"
four-band card. **Card 1 "Your best hours"** is a 24-bucket hourly histogram of
completion times with the best 3-hour window highlighted, a Mochi commentary line, and
two stat tiles. **Card 2 "Day by day"** is seven per-weekday box plots (first-to-last
range, middle-half capsule, typical dot) on the *same* horizontal axis, so the two
cards stack as a matched pair. Both read `CompletedTaskStat` fields that are already
captured: no model change, no migration, no new permission, no rules change.

**Decisions locked**

| # | Decision | Rationale |
|---|---|---|
| D1 | **Two cards, laddered by evidence.** The histogram shows whenever there is data; Day by day appears only when rows qualify. | A new user sees something. Per-weekday slicing needs roughly 7x the data. |
| D2 | **Recurring completions are EXCLUDED from both cards.** | A Monday 8am recurring chore would make Mondays the peak forever. Matches what `ObservationEngine.weekdayCandidate` already does. Note this is deliberately the *opposite* of Effort D12, which includes them: different question, different filter. |
| D3 | **The axis runs 5a to 5a**, not 6a to 11p. | `TimeOfDayBand` already defines the day as starting at 05:00. A 2am completion lands at the far right reading as "late" instead of being clipped. |
| D4 | **Thin rows show the typical dot only.** No capsule, no range bar. | Honest about "we know roughly when, not how consistently", without looking broken. |
| D5 | **A row qualifies for a capsule at 5 completions across 3 distinct dates.** Both Remote Config tunable (`bh_row_min`, `bh_row_dates`). | Low enough to fill in within a month, high enough that a middle-half means something. |
| D6 | **Day by day is hidden on the Week range.** Month and 3 months only. | 7 days is at most 1 sample per row. A box plot of one point is a lie. |
| D7 | **Stats only. Nothing goes in the Journal.** | The Journal follows record-not-grade and has no range picker. A best-hours chart is a grade. |
| D8 | **The rhythm card's VIEW is deleted; `TimeOfDayBand` the TYPE stays.** | `ObservationEngine` depends on the type. Only the UI retires. |
| D9 | **"busiest on Mondays" is dropped from the trend card caption.** | Superseded by Day by day, and it was computed wrong (see below). |
| D10 | **"In window %" reuses the suggestion engine's existing 180-minute window** (±90 around the peak). | Same definition means the number can never contradict the suggestion chip. |

**The caption is generated from chart state, not drawn from a pool.** Four states, in
priority order, all in the pet's voice, all qualitative (no percentages):

| State | Condition | Line |
|---|---|---|
| Second wind | a secondary window clears its floor | "You get the most done in the {peakBand}, with a smaller second wind in the {secondaryBand}. {name} sees it." |
| Thin days | Day by day qualifies but ≥1 weekday row is still thin | "{name} has a good read on your week. {thinDays} are still quiet." |
| Full read | Day by day qualifies and every row has a capsule | "You get the most done in the {peakBand}. {name} sees the pattern." |
| Learning | histogram only; Day by day not yet earned | "Still learning your week. Here's your day so far." |

`{peakBand}` and `{secondaryBand}` are `TimeOfDayBand` names, never clock times, so the
line reads warm and never contradicts the tiles. `{thinDays}` is a natural-language
join with a weekend fold when Sat and Sun are both thin. There is **no FNV-1a rotation**
here: that system is for static pools, and the state itself is the variety.

**The second-wind floor exists so Mochi never narrates noise.** Name a second wind only
when its own window holds ≥ `bh_second_wind_min` completions across ≥
`bh_second_wind_dates` dates AND its share is ≥ half the peak window's share. The
original comp's "8p second wind" sat under 3% of completions and would fail this, which
is exactly the point.

**Stat tiles: PEAK (a range, "10a to 1p") paired with IN WINDOW (%).** An arithmetic
mean is meaningless on a wrapped axis, which is the reason `circularCenterMinute`
exists. The range form was chosen over a single circular-median "Typical" time because
peak-range plus in-window is the same fact stated two ways, both computed from the ±90
window (D10), so no circular-median path is needed on this card.

**Day picker (comp turn 3).** A pill under the eyebrow ("All days" or a weekday) plus
tappable rows; picking a day swaps the card's middle for that day's own 24-bucket hour
curve on the shared axis with day-scoped mini tiles. Pickable means any day with data
(bars show, they don't claim), but the tiles and the peak highlight wait for the row's
D5 floor, so two data points can never mint "100% in window". Selection is view-state
only: reset on screen entry and range change, never persisted.

**`BestHoursHelpView`** (route key `you.stats.help`, reached from a
`questionmark.circle` on both card headers) is a general explainer in the pet's voice:
the histogram and its tiles, the 5a-to-5a clock, the Day by day anatomy with live
swatches, and what counts (recurring exclusion, evidence patience, completion-zone
dating). No user-specific numbers; the cards carry those.

**Known accepted costs.** The 5a-to-5a axis leaves roughly the right quarter of both
cards empty for a normal-schedule user; a dynamic axis would break the match between
the two cards and make one month incomparable to the next. And the two cards add ~600px
to an already-long screen, accepted inline with no collapse: they are self-gating (D1,
D6), and a default-collapse disclosure would introduce the one expand/collapse
component the app deliberately lacks, for a single card.

**Bug that died with D9.** `StatsViewModel.busiestWeekday` took the weekday from the
device's *current* calendar rather than the stored `completedLocalDate` /
`completionTimeZone` like every other card, so it disagreed with the rhythm bands after
travel. It was also ungated, which is why the Journal deliberately refused to carry it.
D9 removed its only consumer, so it died with the caption rather than needing a fix.

---

### Suggestion reach: weekday fallback · row badge · push counting

Three independent changes to the shipped Feature 5 machinery. No new permission, no
rules change. **A and B do not compound**, and the batch should not be judged as if
they do: weekday filtering is viable only at list and global scope, while re-timing is
series-scoped with no fallback. A improves *new-time* suggestions; B improves discovery
of *re-time* suggestions, which fire at exactly today's rate.

**A · Weekday as a fallback on silence**

| # | Decision | Rationale |
|---|---|---|
| A1 | **Weekday is a fallback, not a tier.** Retried only after the pooled answer is silenced by the runner-up-margin gate. | Zero regression risk. Nothing that qualifies today changes. |
| A2 | **List and global scope only. Never series.** | A 42-day window holds at most **6** of any given weekday, and the series floor is 8 completions across 5 dates, so a weekday-filtered series scope is structurally unreachable. |
| A3 | **Weekday-filtered scopes get their own, lower floors** (`suggest_weekday_min` 4, `suggest_weekday_dates` 3). | A weekday slice has roughly 1/7 the evidence. Reusing the pooled floors would make the fallback never fire. |
| A4 | **Provenance is recorded as a type, never a string.** `DistributionResult.Scope` and `SuggestionScopeTier` express "list, this weekday" and "global, this weekday". | `SuggestionCopy` is tier-typed so global can never wear list phrasing. A weekday answer needs its own phrasing and must not borrow the pooled voice. |

*The user this unlocks:* someone who does a chore at 8am on weekdays and 2pm on
weekends has a textbook bimodal history. The runner-up gate silences them, working
exactly as designed, and no amount of additional data will ever change that. The
fallback is the only path that reaches them.

*Weekday chip copy,* deliberately using a distinct verb ("wrap up" vs the pooled
"finish things") so a user who sees both over time does not hear a template:

| Scope | Line |
|---|---|
| weekday + list | "On {weekday}s, {list} usually gets done in the {band}." |
| weekday + list, name gone | "On {weekday}s you usually wrap up in the {band}." |
| weekday + global | "On {weekday}s you usually wrap up in the {band}." |

**B · Re-time row badge**

| # | Decision | Rationale |
|---|---|---|
| B1 | **A badge, not an action.** Tapping the row does what it always did: opens the editor, where the existing chip explains and offers the time. | The problem is discoverability, not capability. No new navigation, no new tap target. |
| B2 | **`clock.arrow.circlepath` in the accent tint.** Not a warning triangle, not a red dot, and not a plain clock. | Mochi never scolds. The real row already shows a `clock.fill` for the `.due` state, so a plain clock would collide; clock-plus-cyclic-arrow reads "adjust the time" and stays distinct even when both appear on one row. |
| B3 | **Icon only. Never the suggested time as text.** | Rows already carry title, due time, list dot, priority chip. "usually 9:20p" competes directly with the real due time inches away and truncates on long titles. |
| B4 | **Evaluated once per fetch and cached with the list. Never per row render.** | The engine is pure over already-fetched stats (CPU, not network), but a naive implementation re-evaluates the gate for every recurring timed task on every render. |
| B5 | **Re-time only. Not new-time.** | A "Mochi suggests a time" badge on every undated task would be noise. |
| B6 | **Tasks tab and ListDetail only. NOT Home's today list, and never a Reminders row.** | Home rows are the most space-constrained, and Home is a today view while re-time is about a recurring series' habitual time. Discovery still happens wherever people browse. |

*Mechanism:* `TodoItemRow` is a single shared component called by Home, Tasks, and
ListDetail, so B6 is enforced by a caller-supplied `showsRetimeBadge` flag on the Tasks
and ListDetail row-item models and **not** on Home's. It is computed once per fetch,
forced false for Apple Reminders rows, and the badge sits immediately after the meta
text, left of the list dot. Home never sets it, so the badge can never appear there.

**C · Push counting**

| # | Decision | Rationale |
|---|---|---|
| C1 | **Increment on any user move of an incomplete task's due date to a LATER date.** Adds the editor date-edit path to the two snooze paths that already counted. | The editor is how most people actually push a task, and it counted nothing. |
| C2 | **Do NOT increment on:** moving a date earlier, skip-occurrence, vacation triage reschedule, or `RecurrenceRoller` auto-advance. | Different intents. The roller has its own `missedCount`; triage is a bulk system-offered action. |
| C3 | **Parse `rescheduleCount` in `taskItem(id:data:)`.** | It was write-only. The only reader was the completed-stats query, which filters on `completedAt`, so a task pushed five times and never finished was invisible to the entire app. |
| C4 | **Ship this first, regardless of when anything consumes it.** | The only time-sensitive item in the batch: push history cannot be reconstructed retroactively. |

There is still **no consumer** for `rescheduleCount` beyond the existing peak-shaping
reschedule weight. A "you have pushed this five times" surface is a later, separate
decision, deliberately out of scope.

**Dead code found in passing:** `missedCount` and `lastMissedAt` are written correctly
by `RecurrenceRoller.rollForwardTask` and read nowhere in the app. They are the natural
signal for a future "this recurring task keeps getting missed" feature and are already
accruing.

---

### Effort size

An **optional effort rating** labeled "Effort", chosen from four magnitude levels
(**Tiny · Small · Medium · Large**) rather than a difficulty or points scale, and
without ever showing the user a clock time. Each level maps internally to a nominal
duration, which weights `MoodEngine` momentum so one big task lifts Mochi about as much
as several small ones, and gives Stats a genuinely new number a completion count cannot
express. **The coin economy stays flat.**

**The problem, precisely.** `MoodEngine` already weights `TaskPriority` at 1 / 1.5 / 2,
but applies it **only to overdue incomplete tasks**, i.e. only on the stress side. On
the credit side momentum is an unweighted count, so one task of any size earns 33% of
max while three trivial tasks earn 70%. That gap is the entire feature.

**How the framing landed.** The path was iterative: difficulty scale → duration
(answerable, calendar-usable) → hide the clock, show qualitative labels → a food
metaphor (Nibble/Snack/Meal/Feast) that tested as unclear because it hid the dimension
being estimated → the final "Effort" label. The end state satisfies every pressure: the
stored value is nominal minutes, the visible control names its dimension, and it shows
no clock.

**Decisions locked**

| # | Decision | Rationale |
|---|---|---|
| D1 | **Labeled "Effort", four magnitude labels, no clock times in the picker.** | Explicit durations felt like a rigid timebox; a food metaphor read as "a random quirky thing". "Effort" names the dimension outright, which is the question the user can actually answer. |
| D1a | **Each label maps to a nominal duration; the stored value is minutes** (`estimatedMinutes: Int?`). Tiny 15 · Small 30 · Medium 60 · Large 120. | Momentum and the Stats total operate on minutes. Only four values are ever written, so minutes→label is an exact lookup. The minutes are internal and never shown. |
| D1b | **The abstract scale is acceptable beside Priority ONLY because two guards hold:** an explicit "EFFORT" eyebrow beside "PRIORITY", and a different control shape (a pill and menu, never a second chip ladder). | An *unlabeled* difficulty scale was the original rejection reason, not abstraction itself. Watch item: "Med" (priority) and "Medium" (effort) can both appear on one row; tolerable under different labels and shapes, revisit if it reads as a duplicate. |
| D2 | **Optional, empty by default.** | Users who ignore it pay nothing. |
| D3 | **Weights: unset 1.0 · Tiny 1.0 · Small 1.4 · Medium 2.0 · Large 3.0.** All Remote Config tunable. | Derived from the intent that one big task should be worth about three small ones. |
| D4 | **Unset is never penalized.** | Otherwise labeling a task "Tiny" would cost momentum versus leaving it blank, and nobody would honestly size a small task. Unset and Tiny being identical is intended: sizing a small task is a no-op on mood, so honesty is free. |
| D5 | **Affects momentum and Stats. Coins stay flat.** | Coins buy treats; a currency with a self-declared multiplier is the most gameable surface in the app. `RewardsStore` had already rejected priority scaling for the same reason. |
| D6 | **`CompletedTaskStat.estimatedMinutes` is a READ-path change only.** | The stat is never written; it is constructed off the task document. No write-path change, no migration, no backfill. |
| D7 | **Do NOT touch `ComfortBufferStore`.** | Completions never touch the buffer today (pets and treats only). Keep that boundary. |
| D8 | **The control shares the Priority row under its own EFFORT eyebrow. No eighth block.** A compact right-aligned pill opening a menu of the four levels plus Clear; unset reads "Set effort" in the muted style. | The editor has seven always-visible blocks and must not gain an eighth. Two chip groups side by side would simply wrap, producing the eighth row by another route. |
| D8a | **The pill lives in exactly one place, by Priority. It is NOT echoed in the Time block.** | An undated task still deserves a size and has no Time block to echo into, so one home is the only consistent rule. |
| D9 | **Duration is credit-side only. Priority keeps the stress side.** An overdue 2h task accrues no more stress than an overdue 15m one. | Two weights on two axes stay legible. Stacking duration onto stress makes a bad day tank twice over. |
| D10 | **The "crushed it yesterday" check stays UNWEIGHTED.** | It is a count of *things done*. Weighted, two long tasks would announce "you crushed it yesterday", which is plainly false. |
| D11 | **"2h+" resolves to exactly 120 minutes for any consumer needing a number.** The weight still caps at 3.0. | Weight and length are two uses of one field and need not share a ceiling. Bounds an otherwise unbounded top bucket. Written for the tabled calendar layer, kept because an unbounded bucket is a latent problem for any future consumer. |
| D12 | **Recurring completions ARE included in the effort total.** | Deliberately opposite to Best Hours D2. A daily 30-minute workout is real time spent, and a total that omits it is wrong. |

**Why 3.0 for the top bucket.** Fed into the existing curve with no change to
`momentumSaturation` or `momentumMax`: three Tiny tasks and one Large task both reach a
weighted sum of 3.0 and land on exactly the same momentum (70% of max), one Medium
gives 55%, and one unsized task gives the unchanged 33%. Gaming is self-limiting:
inflating effort buys no coins, and the only effect is a happier pet, which defeats the
purpose of having one. The user is the only audience for the lie. (That safety is a
consequence of the calendar layer being tabled. A block-finding consumer would have
given inflation a real bite by reserving time the user did not need.)

**Momentum is a data type, not an expression** — the largest ripple, and the one most
likely to be underestimated. `MoodForecast` deliberately passes an array of completion
*timestamps*, not a count, so momentum ages out mid-forecast. Weighting momentum
therefore means the array carries a weight per entry, threading through snapshot
construction, the orchestrator request type, the planner, the memories service, and
every direct baseline caller. **The weight is a sidecar on the entry rather than a
replacement for the date**, so the two count-based consumers (`crushedYesterday` and the
notification threshold, both per D10) keep working on `.count` unchanged and only the
momentum path reduces over weights. That is the smaller and safer diff.

**The Stats tile.** Value is the summed nominal minutes rounded to the nearest 30 and
shown as approximate ("~3h"); title "Effort"; subtitle carries coverage ("12 of 34
rated"). The honesty problem is that existing tasks have no rating and the field is
optional forever, so any sum is a floor, never a total. The subtitle is the fix, not a
hidden coverage gate. This is an output aggregate, not an input timebox, so it does not
violate the no-clock rule. Shows "–" only when zero tasks in the range carry an effort.

**The widget needed no work.** `CompleteTaskIntent` queues only a task id plus a
completion context, but the drain re-reads the full document before completing, so the
rating is in hand. No queue schema change, no legacy-decode concern.

**Explicitly not built:** difficulty as a separate axis. A task can be hard but quick (a
difficult phone call) and size misses that. A real cost, accepted knowingly.

**Open confirms.** Whether the Stats total should stay time-based or fall back to an
effort-count subtitle ("mostly Small this month") if a rough hour total feels too
clock-like beside a clockless picker. And nothing surfaces effort in letters or
observations yet, deliberately, until there is real data: "you took on three Large tasks
this week" is the obvious future consumer.

---

### Editor layout (ghost pill) · design locked, NOT built

> ⬜ **Status: design locked 2026-07-25, not built, no design comp exists.**

**The reframe that shrank this item.** "Suggestions" and "best hours" are not two
surfaces; they are one distribution. The editor's suggested-time chip already falls to
global scope and says "You usually finish things in the evening", and that line *is*
best hours made actionable. Best Hours the Stats card is the identical
`CompletedTaskStat` distribution drawn as a chart, and its D10 already forces the chart
to reuse the suggestion engine's ±90 window so the two can never contradict.
Consequently **nothing about best hours needs an editor surface**: a mini-chart or
second hint would duplicate the chip and risk the two disagreeing. This item is only
about the shape of the new-time chip.

| # | Decision | Rationale |
|---|---|---|
| E1 | **New-time renders as a GHOST inside the time pill**, dimmed with a clock glyph while the time is unset, not as a card below it. | A new task has no row to badge, so all new-time discovery happens in the editor. The shipped card disappears the moment the user opens the time wheel, so it is easy to miss. The ghost is visible the instant a date is set and sits exactly where the value will go. |
| E2 | **Re-time keeps the explanatory card, unchanged.** | A re-time proposal is a *different* time than the one already in the slot, so there is nothing empty to ghost into. The split is forced by the data, not a preference. |
| E3 | **One tap on the ghost accepts AND opens the wheel, seeded at the suggested minute.** | Fuses the shipped open-picker and set-time intents into one gesture, giving accept, replace, and no-time with no hidden gesture. |
| E4 | **No time is ever committed without the user tapping the time field.** The ghost is a display state; `hasTime` stays false until the tap. | Kills the false-acceptance risk that ruled out full prefill, and keeps the shipped outcome classifier honest: never-tapped ghost = ignored, tapped = accepted, tapped-then-spun-past-30 = adjusted. |
| E5 | **The ghost carries a dismiss affordance** in the slot the clear-time x uses (free while there is no time). | Preserves the trigger-keyed `SuggestionLedger` dismissal and its 60-minute re-arm. Dismissing returns the pill to "Set time". |
| E6 | **In ghost mode the caption is the reason line only**, not a "{name} suggests 9:20 PM" label. | The time is already visible in the pill; repeating it is redundant. The muted one-liner carries the provenance. |
| E7 | **For new-time the solid pill IS the confirmed state; drop the confirmed card.** Re-time's confirmed behavior is unchanged for now. | After acceptance the accepted time shows solid in the pill, making the shipped quiet-confirmed card redundant. Leaving re-time alone keeps the change small. |

*Not built here:* any chart or sparkline in the editor; any change to when the chip
qualifies (that is the engine's job); and no "Details" disclosure to collapse Priority /
List / Repeat / Notes. The disclosure was the original reason to sequence this item
last, but the row badge and the effort pill both landed at zero row cost, so the
seven-block sheet is not growing and the app has no disclosure component to build on.
Revisit only if a later feature actually adds an eighth always-visible block.

*Open items:* the exact dim treatment that reads as "suggested, not set" in all five
flavors and stays distinguishable from an empty pill; whether tapping should auto-open
the wheel (E3 as written) or accept quietly and open on a second tap; whether re-time
should also lose its confirmed card for symmetry; and a design comp, which does not yet
exist.

---

### Calendar access · TABLED (not cancelled)

> ⛔ **Tabled 2026-07-25.** Nothing in the shipped batch forecloses it; reviving it is
> additive. Full long-form record archived at
> `ProjectDocs/decisions/calendar-decision-record.md`.

**What was proposed.** EventKit access so Mochi could take existing commitments into
account when suggesting a time. Explicitly not a scheduler: *"It shouldn't be a
scheduler, it should just apply a suggested time."* Concretized as **the calendar is a
mask, never a source** — completion history proposes, the calendar may veto and shift to
the nearest free edge, and the calendar never proposes on its own.

**The objection that opened the question,** and its clean fix. A calendar event does not
mean *unavailable*, it means *spoken for*, and sometimes what it is spoken for is the
task itself: a 6–9pm block might be exactly the studying the task describes, so avoiding
it is backwards. The fix, worth keeping if this ever returns: **history outranks the
calendar, always.** The calendar may only veto a time the history is neutral about; it
can never overrule an endorsed peak. Under that rule the study block is never treated as
a conflict, because that is precisely where the history is strongest.

**Why it was cut anyway: every use is redundant, too narrow, or ruled out.**

| Use | Verdict |
|---|---|
| **Recurring commitments** (the exact scope explored in the comp) | **Redundant with completion history by construction.** A standing commitment is already a hole in the distribution: someone with class every MWF morning has never completed a task then, so the distribution already avoids mornings without knowing why. The calendar supplies a *name* for the hole, not a fact. |
| **One-off events** | **Genuinely unknowable from history, but structurally hard to reach.** The engine produces a *minute of day*, not a date, so the check could fire only after the user picked a date, on dated tasks, on dates carrying a non-recurring event. It is also where the objection above bites hardest. |
| **Cold start** (day one, no history) | **Violates the app's own doctrine.** The strongest case, since on day one the calendar is the only signal that exists. But "your evening has no meeting in it" is not insight about the user, it is the absence of a meeting, and it would be the one place in the app where Mochi speaks without evidence. |
| **Block finding** ("this takes 2h, where are 2 free hours?") | **The one irreplaceable use, and the one explicitly ruled out.** History knows when the user *finishes* things, never when they are *free*. But finding a contiguous block is scheduling, and the founding constraint was that this must not be a scheduler. |

The decisive line: the calendar's only irreplaceable capability is the one the feature
was forbidden to have.

**Cost avoided:** a second EventKit permission on top of Reminders plus its denied and
lapsed states; an onboarding screen; a foreground re-check for existing users; an App
Store privacy disclosure for calendar data; a permanent third-party data dependency with
a new failure mode where a stale calendar produces a wrong suggestion; and the chart
work (hatch layer, header chip, free-time label).

**Two triggers should reopen it:** Mochi starts suggesting a **date**, not only a time
(the one-off case becomes load-bearing the moment a specific-day conflict is knowable),
or **block finding is reconsidered** (Effort D11 already fixes a block length, so the
input side is ready). If revived, `Permissions/RemindersGateway.swift` is a working
template for the exact shape, including the hard boundary that EventKit types never
leave the file; carry forward "history outranks the calendar" and "recurring-only was
the wrong scope, one-offs are the half worth having".

**The cheap substitute,** if the explanatory value is ever missed: a user who wants
Mochi to know they are in class 9–12 MWF can express it as a recurring task or a
quiet-hours setting typed once. Same named hole, no permission, no sync dependency, no
privacy disclosure.

---

## Tech & infrastructure

- **Firebase Auth** — Continue with Apple / Google; anonymous-first, linked on signup.
- **Firestore** — task data + user profile + coins + entitlements; enable offline
  persistence (a reminders app must work offline).
- **Mood engine runs on-device** — time-based, works offline, drives *local*
  notifications. Deterministic, so every device computes the same baseline from the
  same synced task data (no drift); only coins + buffer are synced state. Store the
  tuning constants (`BASE`, `TAU_S`, …) in **Firebase Remote Config** to retune the
  mood curve without an app update. Only reason to add a server later: shared/household
  Mochi or other server-triggered events.
- **Notifications** — local notifications for scheduled mood pings + morning rundown;
  FCM only if server-driven pushes are ever needed. Respect quiet hours + daily cap.
- **Widgets** — WidgetKit extension reading the App Group; **static** mood assets (never Rive);
  home-screen **tap-to-pet + complete-a-task** via App Intents (iOS 17+); lock-screen tinted
  glyph + next task; timeline driven by the notification forecast. Still images, not live
  animation; refresh ~15–60 min automatically + instantly on foreground/intent (those don't
  count against the ~40–70/day budget). **Full spec: → *Widgets*.**
- **Subscriptions** — StoreKit via **RevenueCat** (plays well with Firebase; handles
  trials, restore, entitlement checks).
- **EventKit** — optional Apple Reminders import; full-access reminders permission +
  `NSRemindersFullAccessUsageDescription`. iOS-only.

### Multi-device (v1 guardrails)

> 🆕 **v0.3 — RESOLVED (minimal).** Full multi-device design is deferred; these two rules
> just prevent data corruption in the meantime:

- **Coin writes must be atomic** — `FieldValue.increment()` or a Firestore transaction,
  never read-modify-write — so concurrent or offline-replayed writes can't lose or
  duplicate coins.
- **The comfort buffer is device-local** (App Group state, not synced). Petting on the
  phone doesn't comfort the iPad's Mochi. Odd but acceptable, and it avoids a whole sync
  subsystem. This is a deliberate decision, not an accident.

## Feature backlog / ideas

- **Vacation mode** *(✅ RESOLVED in v0.5 — promoted out of the backlog)* — pause the
  nudging entirely for travel / rest / sick days. See *Vacation mode.*
- **Celebration states & animations** — big dopamine on the upside.
- **Focus / Pomodoro mode** — Mochi cheers you on during a session.
- **Streaks & gentle stats.**
- **Growth / evolution** or **pet friends** — long-term, possible far-future scope.
- **Shared / household Mochi** — co-op pet for shared chores (far-future).

---

## Guiding design principle

> **Mochi doesn't get sad to punish you — Mochi gets stressed *with* you, and
> helping Mochi is a stand-in for helping yourself.** Delight leads; the nudge is
> gentle, capped, and pausable.

## Remaining agenda / roadmap

> 🆕 **v0.3** — tracking the open design-discussion items and where each stands.

| # | Topic | Status | Notes / standing recommendation |
|---|---|---|---|
| 1 | Recurring tasks × mood engine | ✅ **Resolved** | See *Task management → Recurring tasks.* |
| 2 | Entitlement / post-trial states | ✅ **Resolved** | See *Entitlement & subscription states.* |
| 3 | Notifications | ✅ **Resolved** | Copy, constants, actions, winback, instrumentation, mood-ping technical requirements & dev inspector tab all locked. See *Notifications.* |
| 4 | Vacation-mode re-entry | ✅ **Resolved** | Freeze-and-triage, fixed + open-ended end dates with a 30-day auto-expiry cap, truly-silent period, streak-freeze, grace buffer, full UI specs & edge-case matrix. See *Vacation mode.* |
| 5 | `linkWithCredential` collision | ⬜ **Pending write-up** | Understood; needs a handler spec: catch `credential-already-in-use` → `signInWithCredential` into the existing account (real history always wins) → optionally migrate this session's task → delete the orphaned anon user + its Firestore subtree. Also persist Apple's name/email on first authorization (given only once). |
| 6 | Reduce-motion / static pose set | ⬜ **Pending** (external dependency) | Commission **8 static poses** (6 expressive mood states + **asleep** + **resting/holiday**) *with* the Rive rig — they serve widgets, reduce-motion users, and VoiceOver anchors. Widget spec (v0.6) adds a hard **lock-screen constraint: every pose must read as a monochrome silhouette** (anxious-vs-content can't rely on hue). Must be in the animator brief, so this jumps the queue if hiring soon. |
| 7 | Analytics / instrumentation | ⬜ **Pending** | Firebase Analytics + Crashlytics (in-stack) + RevenueCat's built-in subscription funnel. Must-have metric: **daily mood-state distribution across users** — the single readout of whether the product philosophy is working. |
| 8 | Small pile | ⬜ **Pending** | Widget memory ceiling (mood engine in a shared target; never load Rive in the widget); localization (String Catalogs from day one, English-only v1); morning-rundown ranking (drafted above); task-content privacy (no E2E v1, never log titles to analytics/Crashlytics). |
| 9 | Widgets (home + lock) | ✅ **Resolved** | WidgetKit extension + shared engine framework, App Group contract (`MochiWidgetState`), forecast-driven timeline, tap-to-pet + **complete-from-widget in v1**, iOS 26 `fullColor`, vacation = resting pose (distinct from lapsed). See *Widgets.* |
| 10 | The Personal Layer | ✅ **Resolved and shipped (v0.8)** | All six features specced in v0.7 and built in the pinned order 1 → 4 → 3 → 2 → 5 → 6, ending with the Journal tab. See *The Personal Layer* and, for the Journal, `Mochi-journal.md`. |
| 11 | The discovery batch | 🟡 **3 of 4 built** | Best Hours & Day by day, Suggestion reach, and Effort size shipped July 27 2026. Editor layout (the ghost pill) is design-locked and unbuilt with no comp. Calendar access was tabled with a full record. See *The discovery batch.* |
| 12 | Waking-Mochi onboarding | ⬜ **Exploring** | Replace the passive Meet Mochi carousel with a tap-to-wake adoption sequence (asleep → groggy → awake → adopted → name). Needs a design pass, a comp, and two new poses. See *Onboarding → Exploring: the waking-Mochi adoption beat.* |
| 13 | List time-of-day observation | ⬜ **Specced, unbuilt** *(Aug 2 2026)* | A sixth observation type surfacing the Feature 5 list-tier insight ("{list} things usually get done in the evening") on the Journal's noticed card. Divergence-gated against the global band, one incumbent, Journal-only v1, 4 new `obs_list_tod_*` RC keys. See *The Personal Layer → Feature 4 → Extension.* |

## Still to flesh out

- **Screens not yet designed:** paywall, sign-in, onboarding, notification primer,
  Apple Reminders settings, account & legal section of "You." *[v0.8: onboarding now
  has a direction to design against, the waking-Mochi adoption beat.]*
- **Design comps not yet made:** the editor ghost pill (the last unbuilt discovery-batch
  item) and the waking-Mochi onboarding sequence. Both want a pass in the Claude Design
  project. Shipped-asset gaps are tracked separately in `waiting-on-assets.md`.
- **Notification mechanics** — *[v0.4: fully resolved — copy, constants, actions, winback,
  instrumentation, mood-ping technical requirements & dev inspector tab all locked. See
  Notifications.]* Remaining is a writing pass on the line-by-line copy strings + numeric
  tuning on real data (both Remote Config).
- **Procrastination signal (v2)** — repeated snoozing never triggers "overdue," so
  Mochi never notices. Detect chronic rescheduling.
- **Accessibility** — mood conveyed beyond color/sound (VoiceOver labels), reduced-motion.
  *[v0.3: see roadmap #6 — the static pose set is the shared fix for reduce-motion + widgets
  + VoiceOver.]*
- **Platform scope** — *[v0.5: DECIDED — iOS only. Android is not planned. The stack
  (Apple/Google auth, lock-screen widgets, Watch, Apple Reminders) leans iOS and we're
  committing rather than hedging.]*
- **Empty states** — "nothing due today" (calm) vs "all caught up" (celebration). Both
  mocked; keep them distinct.

---

## Open questions

1. Exact bedtime default (e.g. 10pm–7am?) and morning-rundown send time.
2. Diminishing-returns curve for coins — how many full-value completions per day
   before it tapers?
3. The task app itself: recurring tasks / routines, subtasks, tags, priorities —
   which make the first version vs. later? *[v0.3: recurring resolved (see Task management →
   Recurring tasks); priorities in v1; subtasks & extra tags out of v1; lists cover the
   tag need.]*
4. Onboarding flow — how do we introduce Mochi and set expectations in the first
   30 seconds?
