# Feature 2 Implementation Guide · Anniversaries & Memory Callbacks

> Personal Layer build order: 1 → 4 → 3 → **2** → 5 → 6. Features 1, 4, 3 are shipped.
> Spec: `mochi-requirements.md` § "Feature 2 — Anniversaries & memory callbacks" (lines ~1984–2237).
> This guide maps every spec requirement to concrete code, in the mandated architecture
> (DesignDocs: stores injected via `AppContainer`, pure domain functions, no singletons).

---

## 1. Scope in one paragraph

Sparse relationship milestones (1 week, 1 month, then yearly) computed from write-once
`adoptedOn`, plus four kinds of mood-gated positive memory callbacks (best day, recovery,
streak era, date echo), delivered **entirely on existing rails**: one Personal-Layer line in
the morning rundown, and the `CelebrationCenter` banner on the day's first open. No new
notification class, no new slots, no new push. New synced field `bestStreakAchievedOn`.
Six new `callback_*` Remote Config keys. Letter milestone beat learns anniversary references
(closing Feature 3's documented gap).

## 2. What exists vs. what must be built (from codebase survey)

Already in place and reused verbatim:

| Rail | Where | Reused for |
|---|---|---|
| Rundown planning + fire-time dress | `Notifications/NotificationPlanner.planRundowns`, `NotificationRequestBuilder.request` `.rundown` case (`NotificationScheduling.swift`) | injection point for the Personal-Layer line |
| Fire-time evaluation precedent | `RundownRanker.topTasks(from:at:calendar:)` | register + facts evaluated at `plan.fireAt` |
| Baseline vs displayed mood | `MoodForecast.baseline(at:snapshot:)` vs `.displayed(at:)`; buffer is device-local (`UserDefaultsComfortBufferStore`) | `RundownEmotionalRegister` bands **baseline**, never displayed |
| Taper state | `TaperTracker` + `NotificationPlanner.floorDayOrdinals` | chronic-taper tier of the register |
| Provider-hook pattern | `NotificationOrchestrator.letterInputProvider` wired in `AppContainer` | `personalLayerInputProvider` |
| 132-day stats fetch | `ObservationService.engineInputs(now:calendar:)` (replay 90 + window 42) | callback fact mining, **no new query** |
| Lateness computation inputs | `CompletedTaskStat.dueAt/hasTime/completedAt/completionTimeZone` | recovery episode mining |
| Per-UID cadence ledger pattern | `ObservationLedger` (UserDefaults JSON, version gate, weekly cap, told-once list, CopyDeck) | sibling `CallbackLedger` (own namespace + schema version, so observation `algorithmVersion` bumps never wipe callback state) |
| Interval log | `ObservationInterval` on profile, `contains(_:)`, `logSince` honesty rule | vacation deferral + "first rundown after re-entry" |
| Copy templating + rotation | `PetCopyTemplate.render`, `CopyDeck` | all new pools |
| Streak engine | `RewardsStore.awardCompletion` (`let best = max(previousBest, streak)`), `StreakMilestones`, `CelebrationCenter` | `bestStreakAchievedOn` stamp, collision rule, banner |
| Letter beat library | `LetterComposer` milestone beat (streak-only today), `PeriodSummary.adoptedOn` already threaded | anniversary + collision copy |
| Telemetry pattern | `ObservationTelemetry` os_log protocol, ledger-throttled denominator | `callback_evaluated` etc. |
| Remote tuning pattern | `RemoteTuning` five-touch-point key pattern, tests pin key set (`== 54` guard) | 6 `callback_*` keys |

Must be created (nothing like it exists): the **canonical Personal-Layer priority selector**
(streak milestone > anniversary > crushed yesterday > callback > observation), the
`RundownEmotionalRegister` type, all of the `Memories/` domain module, `bestStreakAchievedOn`
end to end, and the letter collision copy.

## 3. New module: `MochiBuddy/Memories/`

Screaming-architecture folder for "anniversaries and memory callbacks". Pure domain logic in
enums of static functions (ObservationEngine precedent: explicit `now`/`calendar` params, zero
clock reads); one `@MainActor` service assembling inputs; one sibling ledger.

```
Memories/
├── AnniversaryCalendar.swift      // pure date math: milestones, clamps, vacation deferral
├── CallbackFacts.swift            // CallbackType, CallbackFact, canonical factId
├── CallbackFactMiner.swift        // pure mining over [CompletedTaskStat] + streak fields
├── RundownEmotionalRegister.swift // register tiers from predicted baseline + taper
├── PersonalLayerPlanner.swift     // THE canonical priority + deterministic selection contract
├── CallbackLedger.swift           // per-UID cadence state (device-local, documented limitation)
├── CallbackConstants.swift        // the 6 remote-tunable values
├── MemoriesCopy.swift             // anniversary + callback pools, recovery family restricted
├── MemoriesService.swift          // @MainActor orchestrator: assembles PersonalLayerInput, banner check
└── CallbackTelemetry.swift        // os_log events, no payloads
```

### 3.1 `AnniversaryCalendar` (pure)

```swift
enum AnniversaryTier: Equatable { case week, month, year(Int) }   // 1 week, 1 month, then yearly
struct AnniversaryMilestone: Equatable { let tier: AnniversaryTier; let localDate: String }

enum AnniversaryCalendar {
    // "Is fireAt's local date a milestone date?" Date-only math from adoptedOn, no stored state.
    static func milestone(adoptedOn: String, onLocalDate: String) -> AnniversaryMilestone?
    // Calendar clamps: Jan 31 adoption -> Feb 28/29 month mark; Feb 29 -> Feb 28 in non-leap years.
    // Uses the platform's own clamping (fixed UTC Gregorian calendar over date-only components,
    // AdoptedOnDate parsing precedent).

    // Month-and-larger milestones whose date fell strictly inside a closed vacation interval.
    static func deferredAcknowledgment(adoptedOn: String,
                                       intervals: [ObservationInterval],
                                       firstWakeAfterReentry: Date,
                                       previousWake: Date,
                                       calendar: Calendar) -> AnniversaryMilestone?
}
```

Deliberately **not** remote-tunable (calendar facts, not levers). The deferral is computed
statelessly: the rundown at `fireAt` is the first post-re-entry rundown iff a vacation interval
closed inside `(fireAt - 1 day, fireAt]`; if a month+ milestone date fell inside that interval,
the acknowledgment line rides this one rundown. Week-tier milestones passed on vacation are
skipped (too small to backdate). Toggle off → no rundown → skipped, deliberately.

### 3.2 `CallbackFacts` + canonical fact identity

```swift
enum CallbackType: String, CaseIterable { case dateEcho, recovery, bestDay, streakEra }

struct CallbackFact: Equatable {
    let type: CallbackType
    let factId: String        // canonical, CROSS-TYPE (once-until-changed identity)
    let sourceLocalDate: String?  // for coarse relative time + within-type recency ordering
    // payload fields per type: count, tied flag, streak count, era date...
}
```

Canonical `factId`s (spec-pinned):
- best day AND date echo: `completion-day-{localDate}` (same day can never be told twice across the two types)
- recovery: `recovery-{fnv1a of sorted contributing task/series ids + window start local date}`
- streak era: `streak-record-{count}-{achievedOn}` (`legacy` sentinel when `bestStreakAchievedOn` is nil; legacy dates are never guessed)

### 3.3 `CallbackFactMiner` (pure)

Inputs: `records: [CompletedTaskStat]` (the existing 132-day fetch via
`ObservationService.engineInputs`), streak fields from the synced profile
(`streakCount`, `bestStreakCount`, `bestStreakAchievedOn`, `lastActiveDate`), `adoptedOn`,
explicit `now`/`calendar`. Output: `[CallbackFact]`, all floors applied.

Evidence floors (spec table):
- **Best day**: ≥ `callback_best_day_min` (5) completions from ≥ 5 distinct identities
  (`seriesId ?? taskId`) on one `completedLocalDate`. Standout = max count; tie → latest
  qualifying day wins, `tied` flag drives "one of your biggest days" copy. Fact age ≥
  `callback_fact_age_days` (7).
- **Recovery**: overdue clears (lateness > 0, computed from `dueAt`/`hasTime` in the record's own
  `completionTimeZone`, same boundary rule as ObservationEngine: timed → `dueAt`, date-only →
  end of due day) clustered in 48h windows; qualifying = ≥ 3 distinct identities AND ≥ 1 clear
  ≥ 24h overdue. Episode end ≥ 7 days old. Deliberately lighter than Feature 4's comeback
  (one true episode, not a personality).
- **Streak era**: best ≥ 7. Suppressed while the record belongs to the active streak AND that
  streak produced a milestone celebration within `callback_streak_quiet_days` (14): the active
  run's milestone M's achievement date is derivable as `lastActiveDate - (streakCount - M)` days.
  Fact age: achieved ≥ 7 days ago unless the run has since ended. Era phrasing only with
  `bestStreakAchievedOn`; legacy records get count-only copy.
- **Date echo**: today minus k calendar months (k ≥ 1, clamped like milestones) clears the
  best-day floor including distinct identities. Date-bound, exempt from the fact-age floor.
  Never claims "cleared your whole list" (counts are provable, emptiness is not).

Relationship activation: no callbacks before `callback_min_age_days` (21) after `adoptedOn`.

### 3.4 `RundownEmotionalRegister` (pure)

```swift
enum RundownEmotionalRegister { case open, recoveryOnly, closed }

static func evaluate(fireAt: Date, snapshot: MoodSnapshot,
                     taper: TaperState, calendar: Calendar) -> RundownEmotionalRegister
```

Bands `MoodForecast.baseline(at: fireAt, snapshot:)` (there is no baseline-band helper today;
`MoodForecast.band(at:)` bands **displayed** and must NOT be used):
- `.content` and above → `open` (any callback type)
- `.uneasy` / `.anxious` → `recoveryOnly` (the one fact that is about getting out)
- `.verySad`, or a projected chronic-taper day (floor ordinal ≥ 3 folded forward from
  `TaperState` across the forecast, `floorDayOrdinals` precedent) → `closed` (taper's
  pure-presence copy owns that register)

Buffer lift changes nothing by construction (baseline never includes boosts); two devices with
different comfort buffers compute the same register from synced data. The register gates
**callbacks only**. Anniversary lines ignore it (a date is not a demand, edge case 10).

### 3.5 `PersonalLayerPlanner` (pure): the canonical priority + selection contract

One source of truth for **streak milestone > anniversary > crushed yesterday > callback >
observation**, applied to the rundown line and (via `MemoriesService`) the banner.

```swift
enum PersonalLayerLine: Equatable {
    case crushedYesterday                       // existing title override, now priority-governed
    case anniversary(AnniversaryMilestone)      // opener line
    case deferredAnniversary(AnniversaryMilestone) // post-vacation past-tense ack
    case callback(CallbackFact)                 // opener line
    case observation(QualifiedObservation)      // opener line (Feature 4 finally gets its rundown consumer)
}

struct PersonalLayerAssignment: Equatable { let localDate: String; let line: PersonalLayerLine }

static func assign(rundownDates: [(fireAt: Date, localDate: String)],  // horizon, ascending
                   input: PersonalLayerInput,
                   ledger: CallbackLedger.State,
                   calendar: Calendar) -> [PersonalLayerAssignment]
```

Locked semantics:

- **Streak milestone claim (same-date collision rule).** A date is streak-claimed when the
  milestone is *eligible* on that local date: the continuing streak's next count is a milestone
  (`lastActiveDate == date - 1 && StreakMilestones.isMilestone(streakCount + 1)`) or it was
  already reached today (`isMilestone(streakCount) && lastActiveDate == date`). A streak-claimed
  date renders **no Personal-Layer rundown line at all**: streak celebrations are in-app only
  (v0.6.1 locked), so the claim suppresses the anniversary (and everything below) on rundown and
  banner without inventing a notification-borne streak surface. The letter may still carry both.
  Under Feature 1's first-active-day semantics day-7 and week-1 can land same-date or adjacent;
  the rule never assumes either (edge cases 1 and 2).
- **Anniversaries are never deferred to a free day** (announcing a date on the wrong date is a
  small lie). Lost anniversary → the letter remembers.
- **Callback selection (deterministic):** type priority date echo > recovery > best day >
  streak era; within a type never-told beats told-and-since-changed, then most recent
  qualifying fact, ties by stable `factId` ordering. Below `open`, recovery is the only
  candidate. The whole selection is a pure function of (facts, register, ledger cadence
  state, date).
- **Cadence:** ≤ 1 Personal-Layer line per rundown; ≤ `callback_weekly_cap` (2) per week;
  ≥ `callback_min_gap_days` (3) between scheduled callbacks. Assignments are computed for the
  whole rundown horizon in date order so pre-laid future rundowns respect caps among
  themselves. Only a callback that is actually assigned consumes cadence; a callback that
  loses to a higher line stays fully eligible, except a losing date echo, which expires
  silently on its date (never backdated).

### 3.6 `CallbackLedger` (device-local cadence, sibling of ObservationLedger)

Per-UID UserDefaults JSON under `mochi.memories.ledger.{uid}`, own `schemaVersion`, cleared in
the account-deletion path. State:

```swift
struct State: Codable, Equatable {
    var schemaVersion: Int
    var scheduled: [String: String]     // rundown localDate -> factId (the cadence record)
    var lastEvaluated: [String: String] // CallbackType raw -> localDate (telemetry throttle)
    var bannerShown: [String: String]   // anniversary milestoneId -> localDate shown
    var deck: CopyDeck                  // rotation cursors for all Memories pools
}
```

Re-lay idempotency: each re-lay **replaces** `scheduled` entries for today-and-future dates
with the fresh assignment (a dropped future line un-consumes; the wiped notification never
fires). Past-dated entries freeze: they are the "told once" record. Derived queries: told
factIds = values of past entries ∪ current schedule; weekly cap counts entries per
`weekKey`; min-gap compares day numbers of adjacent entries. **Honest limitation, accepted for
v1 (spec-pinned):** the ledger is device-local, so once-ever and the caps are per-device
guarantees; a second device may tell the same fact once more, identically worded by
determinism.

### 3.7 `MemoriesService` (@MainActor, injected via AppContainer)

- `personalLayerInput(now:) async -> PersonalLayerInput?` : assembles facts
  (via `ObservationService.engineInputs`, no new query), profile streak fields, `adoptedOn`,
  qualified observations, ledger state. Wired to the orchestrator as
  `personalLayerInputProvider` (letterInputProvider pattern). Returns nil while lapsed.
- `checkAnniversaryBanner(now:)` : called on Home refresh. Computes today's milestone,
  guards: lapsed → skip entirely; vacation active → silent (truly silent holds absolutely);
  streak-claimed date → streak owns the banner; already shown today (ledger) → once per day's
  first open. Posts to `CelebrationCenter` (new anniversary slot) and records the ledger.
- Emits `callback_evaluated` (denominator) once per type per user-day with the coarse blocked
  reason: no fact / evidence / fact age / register / priority / gap / weekly cap / already told.

## 4. Data model: `bestStreakAchievedOn`

Contract (spec-pinned): date-only `YYYY-MM-DD`, same calendar semantics as the streak engine,
updated **atomically with `bestStreakCount`** and only on **strict** exceed (equal never
overwrites); as an active record run advances daily the date advances with it; legacy records
never get a guessed date.

Touch points:
1. `UserProfile.bestStreakAchievedOn: String?` beside `bestStreakCount` (nullable-String,
   `adoptedOn` pattern).
2. `UserProfileDTO` decode + `UserProfileMapper` (validate via `AdoptedOnDate.isValid`, nil on
   garbage; never invent a date).
3. `RewardsStore.awardCompletion`: when `streak > previousBest`, stamp
   `AdoptedOnDate.string(from: today)` (today = the engine's own `startOfDay`); else carry the
   stored value forward unchanged.
4. `UserProfileRepository.saveStreak(count:best:bestAchievedOn:lastActiveDate:userId:)`: one
   merge write → atomic. `CachingUserProfileRepository` mirrors.
5. `VacationReentryService` streak freeze passes the existing value through untouched (it never
   sets a record).
6. `StubProfileRepository.saveStreak` in TestSupport gains the parameter.

**firestore.rules: NO change required.** The `users/{uid}` update rule
(`isOwner(uid) && adoptedOnPreserved()`) already permits owner writes of new fields, exactly as
`streakCount`/`observationIntervals` ride it. The spec places strict-exceed monotonicity
client-side and does not ask for a write-once rule (unlike `adoptedOn`, this field must
advance). Documented decision: no new rules function, no redeploy needed for Feature 2.

## 5. Surface wiring

### 5.1 Rundown (the only notification-borne surface)

- `NotificationOrchestrator`: new `personalLayerInputProvider` closure; `makeContext` stores the
  input on `RelayContext`. After planning, `relayNow` runs `PersonalLayerPlanner.assign` over
  the planned rundown dates, commits the assignment to the `CallbackLedger`, and threads the
  per-date lines into `NotificationRequestBuilder.request`.
- `.rundown` dress case: an assigned `anniversary`/`deferredAnniversary`/`callback`/
  `observation` line renders as the **opener line** leading the day's priorities;
  `crushedYesterday` keeps its existing title-override form but now only fires when it wins the
  canonical priority. Streak-claimed dates render no Personal-Layer content.
- Register is evaluated per rundown at `plan.fireAt` (RundownRanker precedent) from the re-lay
  snapshot; every later re-lay refreshes it (predict pessimistically, fix on open).
- Vacation/lapse: planner already lays no rundowns on vacation days and returns promises-only
  while lapsed, so those skips are structural. The deferred acknowledgment rides only the first
  post-re-entry rundown, derived from the interval log, no stored state.
- Budget untouched: the line is content inside the existing rundown slot.

### 5.2 Banner (in-app, day's first open)

`CelebrationCenter` gains a second slot (`pendingAnniversary` + `post`/`consume`); streak
milestone always outranks it on consume. `HomeViewModel.rebuildDerivedState` asks
`MemoriesService.checkAnniversaryBanner(now:)` then consumes streak first, anniversary second,
into the existing celebration banner surface. Notifications denied → the banner still carries
the anniversary (edge case 9). Rundown toggle off → banner still shows; callbacks don't fire
(edge case 8).

### 5.3 Letter milestone beat (closes Feature 3's gap)

- `PeriodSummary.anniversary: AnniversaryFact?` (tier + landed-during-vacation flag), computed
  in `PeriodSummaryBuilder` from `adoptedOn` + the attribution window + vacation intervals
  (a fully-vacation-covered period composes no letter, so "only if a letter otherwise exists"
  is structural).
- `LetterComposer`: milestone beat selection gate becomes
  `!milestonesLanded.isEmpty || anniversary != nil`; render branches three ways: streak-only
  (existing pool), anniversary-only (new pool), collision (new pool, both facts in one beat:
  "Seven days of streak, one week of us"). Anniversary added to `summaryHash`;
  `LetterCopy.version` bumped.

## 6. Remote Config (6 new keys · console publish required, user-owned)

| Key | Default | Clamp |
|---|---|---|
| `callback_weekly_cap` | 2 | 0...7 |
| `callback_min_gap_days` | 3 | 0...14 |
| `callback_min_age_days` | 21 | 0...90 |
| `callback_fact_age_days` | 7 | 0...60 |
| `callback_best_day_min` | 5 | 2...20 |
| `callback_streak_quiet_days` | 14 | 0...60 |

Standard five-touch-point pattern: `ResolvedTuning` fields + `resolve` clamps + `numberKeys`
registration + `apply` into `CallbackConstants` + `RemoteTuningTests` (published set, stub,
expected tuning, count guard 54 → 60). The milestone set (1 week / 1 month / yearly) is
deliberately NOT remote-tunable. There is no 30-day repeat cooldown key: once-until-changed
replaced it.

**Console publish pending after this feature:** the 6 `callback_*` keys join the already-pending
24 `obs_*` + 6 `letter_*` keys (36 unpublished total). Until published, shipped defaults apply,
which equal the spec values, so behavior is correct without console action.

## 7. Instrumentation (os_log, no payloads ever)

- `anniversary_shown`: tier + surface (banner / rundown / deferred)
- `callback_shown`: type + register tier at lay time
- `callback_evaluated`: type + qualified bool + coarse register tier + coarse blocked reason
  (no fact / evidence / fact age / register / priority / gap / weekly cap / already told),
  ≤ 1 per type per user-day via the ledger throttle. The denominator that makes the tripwire
  answerable (caps-binding vs floors-too-tight).
- Never dates, counts, streak values, or fact identifiers.

## 8. Dev tooling

DEBUG `DevMemoriesSection` in the DevScheduler tab (DevObservationInspector pattern): today's
milestone + next milestone date, mined facts with gate-by-gate evidence, register at the
time-travel cursor, ledger dump (scheduled map, banner-shown, deck cursors), sharing the
existing time-travel slider via cached inputs.

## 9. Test plan (spec "Test coverage (required)" mapped)

New files in `MochiBuddyTests` (Swift Testing, `Dates.now` anchor Wed 2026-07-08, constants
pinned by fixture construction, never by mutating process-global tunables):

| Spec bullet | Test file / cases |
|---|---|
| Date math: clamps (Jan 31, Feb 29), yearly recurrence, zone-change date-only comparison | `AnniversaryCalendarTests` |
| Collision rule: same-date streak wins banner + rundown; adjacent days both surface; letter may carry both; table-driven priority list with streak first | `PersonalLayerPlannerTests`, `LetterComposerTests` additions |
| Register gate: predicted baseline + projected taper at fire time; buffer lift changes nothing; three tiers gate types | `RundownEmotionalRegisterTests` |
| Vacation deferral: month+ past-tense on first post-re-entry rundown from intervals; 1-week skipped; toggle-off skips; nothing during the trip | `AnniversaryCalendarTests` + `PersonalLayerPlannerTests` |
| Lapse: skipped, never backdated; next future milestone resumes | `MemoriesServiceTests` |
| Fact identity: once-until-changed per canonical factId; cross-type dedup (best day vs date echo); new date / new episode / strictly-new record re-arm | `CallbackLedgerTests`, `CallbackFactMinerTests` |
| Evidence floors: per-type table incl. distinct identities, recovery ≥ 24h-overdue qualification, fact-age floors, tie rule + tie-aware copy | `CallbackFactMinerTests` |
| `bestStreakAchievedOn`: atomic with count, strictly-exceeded only, equal never overwrites, legacy never guessed, same-run celebration suppression window | `RewardsStoreTests` additions, `CallbackFactMinerTests` |
| Selection contract: type priority, within-type ordering, only-winner-consumes, losing date echo expires, determinism | `PersonalLayerPlannerTests` |
| Register templates: recovery family structurally free of count slots, magnitude comparison, banned constructions | `MemoriesCopyTests` (roughPoolsStructure mechanism: iterate exposed restricted pools, assert no digits, no `{` besides `{name}`, banned substring list) |

Plus: `RemoteTuningTests` updates, rundown dress integration (`NotificationDeliveryTests`
additions: opener line present/absent per assignment, crushed-yesterday now priority-governed),
banner flow (`HomeViewModelTests` additions).

## 10. As-built deltas (implementation notes, July 24 2026)

The implementation matches this guide with four refinements worth knowing:

- The orchestrator hook is named `personalLayerProvider` and takes a
  `PersonalLayerRequest` (rundowns + snapshot + taper + completion times + now),
  because the taper state only exists after `relayNow` folds the current band,
  which is later than `makeContext`.
- The request builder takes a `PersonalLayerSlot` (`.unavailable` / `.none` /
  `.line`) so "the planner ran and chose nothing" (e.g. a streak-claimed date)
  is distinguishable from "no planner wired" (bare tests), which keeps the
  legacy crushed-yesterday fallback for the latter only.
- The ledger stores rendered openers as `{name}` templates (final substitution
  at dress time), so a pet rename re-renders stored lines without burning copy
  rotation; the observation tier gets the same property by rendering through
  `ObservationService.surfaced` with the placeholder as the name.
- A streak-claimed date renders NO rundown line at all: celebrations are
  in-app only (v0.6.1 locked), so the claim suppresses the anniversary and
  everything below without inventing a notification-borne streak surface.

## 11. External setup checklist produced by this feature

1. **Firebase console → Remote Config:** create + publish the 6 `callback_*` parameters
   (values = defaults above). Joins the pending 24 `obs_*` + 6 `letter_*` publishes.
2. **firestore.rules:** no change, no redeploy needed (documented in §4).
3. Everything else is client-side.
