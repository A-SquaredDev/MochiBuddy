# Feature 6 Implementation Guide · Journal Tab

> Personal Layer build order: 1 → 4 → 3 → 2 → 5 → **6**. Features 1, 4, 3, 2, 5 are shipped.
> Spec: `mochi-requirements.md` § "Feature 6 — Journal tab" (lines ~3241–3490).
> Design reference: Claude Design project `a29baf31-09f7-4a61-b4d3-afd8e0191c26`,
> `Journal Tab.dc.html` (states 1a young · 1b growing · 1c rich · 1d lapsed).
> This guide maps every spec requirement to concrete code, in the mandated architecture
> (DesignDocs: stores injected via `AppContainer`, pure domain functions, no singletons).

---

## 1. Scope in one paragraph

A fourth tab (**Home · Tasks · Journal · You**) that is deliberately *only a container*:
no new engines, no new gates, **zero Remote Config keys** (the 74-key pin stays at 74).
Content order: newest **unread letter as hero** (a presentation state of a timeline row,
never a copy) → **one unified story timeline** (letters by reference + moments,
newest-first, month-grouped by **stored** dates and zones) → **"{Name} has noticed"**
observation card → **data footer** (week strip, 4-week trend, done-this-week, best
streak — **no coins, no on-time %, no ungated busiest-weekday**; record vs. grade).
Moments are **synced, create-only, natural-id documents whose ids identify events**
(`adoption-{date}`, `anniversary-{tier}-{date}`, `streak-milestone-{count}-{date}`,
`vacation-return-{intervalId}`, `list-return-{listId}-{firedOn}`) with **deterministic
payloads derived from immutable event facts**. The adoption moment is **atomic** with
`adoptedOn` (batched; deterministic synthesis fallback keeps the Journal non-empty).
Lapsed: everything renders, frozen at **`effectiveNow = lapseStartedAt`**, zero
come-back copy. The Stats module retires; the You tab returns to pure settings.

## 2. What exists vs. what must be built (from codebase survey)

Already in place and reused:

| Rail | Where | Reused for |
|---|---|---|
| Letter model with stored zone | `Letter.timeZoneId`, id `letter-{monday}` (`Letters/Letter.swift`) | timeline dating, stable routes |
| Letter fetch + read sync | `FirestoreLetterRepository.letters`, `markRead`; `LetterCompositionService.markOpened` / `unreadLetter` / `pendingNotificationOpen` | hero + rows + envelope clearing, untouched |
| Letter row + detail | `LetterArchiveBehavior.LetterRow`, `LetterArchiveViewModel.row/weekLabel`, dual-mode `LetterDetailView` (`onBack`/`onClose`) | extracted row component + pushed detail (the promised navigation-only handoff) |
| Week strip / trend derivations | `StatsViewModel.weekCells` / `trendPoints` (Swift Charts) | move into `JournalViewModel` largely intact |
| Adoption date | `PetIdentityStore.adoptedOn`, `AdoptedOnDate` (YYYY-MM-DD, `displayString`) | adoption moment id + young state |
| Anniversary identity | `AnniversaryMilestone.id` == `anniversary-{tier}-{date}` (`Memories/AnniversaryCalendar.swift`) | the natural key, verbatim |
| Milestone detection | `TaskCompletionStore.onMilestone` (count at crossing edge, `AppContainer:241`) | second consumer writes the moment |
| Vacation true end | `VacationReentryService.finish` closes the interval via `ObservationIntervalRecorder.vacationEnded` | vacation-return moment at re-entry |
| List-return events | `ObservationEngine.listReturnCandidate` (`listId` + `firedOn`), ledger key `listReturn:{listId}|{firedOn}`, `Surface.journal` already enumerated | list-return moment id + once-per-event gate |
| Interval log | `UserProfile.observationIntervals`, `openInterval(.lapse)?.start` | `effectiveNow` freeze source |
| Qualified observations | `ObservationService` (pure engine over inputs + now) | the noticed card — finally the `observation_shown` caller |
| Create-only conventions | `activityWeeks` guard-then-set; letters rules create-only | moments repo + rules shape |
| Erasure path | `AccountEraser.eraseAllData` (tasks/lists/letters/activityWeeks) | + `moments` |
| Telemetry pattern | `ObservationTelemetry` os_log, no payloads | `journal_*` events |
| Tab shell | `MainTab` enum + `MainTabView` (3 hardcoded tabs), routers built in `RootView`, shared `homeNavController` | 4th case + `JournalRouter` |

Must be built: `Journal/` module (view/VM/behavior/router, timeline composer, states,
footer, impressions), `Moments/` (model, copy, factory, Firestore repo, five producers,
adoption batch + synthesis), navigation migration (tab, You-row retirement, envelope +
notification rerouting via a shared tab coordinator), rules block, tests.

Survey facts that shaped decisions:

- **`stampAdoptedOn` is not batched today** (`UserProfileRepository:157-164`, two
  independent merges). New API batches profile stamp + adoption moment (§4.3).
- **`ObservationInterval` has no id field** — identity is positional (kind + start).
  The vacation-return `{intervalId}` derives from the closed interval's **start epoch
  seconds** (synced, identical on every device; two same-date intervals differ by start).
- **List name is not captured at event time** by Feature 4 (conclusion carries `listId`
  only) — the moment writer resolves and freezes the name at emission (§4.4).
- **Backfilled vs onboarding-captured adoption is not distinguishable in stored data** —
  so only the *onboarding batch* writes named copy; every synthesized/backfilled moment
  uses the legacy-neutral line (§4.3), which also keeps synthesis deterministic.
- Stats coins/streak read straight off the profile — nothing in the new footer touches
  `RewardsStore`, making the no-coins assertion a pure output check.

## 3. Design-review deltas (from `Journal Tab.dc.html`, agreed direction)

The mockups match the spec's content order and states. Deliberate deviations:

1. **No emojis** (🔥 ✨ ✉ 🍡 ✦ in the mock) — SF Symbols via the established
   convention: `flame.fill` (streak), `sparkles` (anniversary / list return),
   `envelope.fill` / `envelope.open` (letters), `heart.fill` (adoption), `✦` bullets
   become `sparkle` glyphs. Tab icon `book.fill` with a `// DESIGN NOTE:` for
   commissioned art (roadmap #6).
2. **Lapsed "noticed" lines stay frozen verbatim** — the mock's past-tense rewrites
   ("You always came back…") would be *new composition during lapse*. Freezing =
   evaluating with `effectiveNow = lapseStartedAt`; same lines, same tense.
3. **The full footer includes the 4-week trend** the mock omits — the spec keeps it
   (`StatsViewModel.trendPoints` moves over).
4. **Adoption copy branches**: onboarding batch snapshots the just-captured name
   ("You brought {name} home."); backfill/synthesis renders "The day your story began"
   (name-at-adoption unknowable — survey confirmed no snapshot exists).
5. Header subtitle "With {name} since {month}" adopted (relationship age is a record);
   omitted in the young state as in the mock. Lapsed subtitle "{Name} is napping ·
   paused" adopted (status, not come-back copy) with the desaturated treatment.
6. Sample copy in the mock contains an em dash ("Dear you — Thursday…") — illustrative
   only; real letter prose comes from Feature 3's composer, and no new copy uses em
   dashes.

## 4. New module: `MochiBuddy/Moments/`

### 4.1 `Moment.swift` — model + natural identity

```swift
enum MomentType: String, CaseIterable {
    case adoption, anniversary, streakMilestone, vacationReturn, listReturn
    var idPrefix: String {
        switch self {
        case .adoption: "adoption-"
        case .anniversary: "anniversary-"
        case .streakMilestone: "streak-milestone-"
        case .vacationReturn: "vacation-return-"
        case .listReturn: "list-return-"
        }
    }
}

struct Moment: Equatable, Identifiable {
    static let schemaVersion = 1
    let id: String                    // natural key, identifies the EVENT
    let type: MomentType
    let occurredOn: String            // YYYY-MM-DD civil date (AdoptedOnDate currency)
    let renderedTextSnapshot: String
    let accessibilityTextSnapshot: String
    let petNameSnapshot: String?      // as of the event; nil = unknown (legacy adoption)
    let subjectNameSnapshot: String?  // e.g. list name as of the event
    let localeIdentifier: String
    let copyDeckVersion: Int
    let sourceEventId: String?        // provenance where an upstream event exists
    let createdAt: Date
}
```

Natural keys (exhaustive v1, spec table):

| Type | Id | Source of each part |
|---|---|---|
| adoption | `adoption-{adoptedOn}` | write-once profile field |
| anniversary | `anniversary-{tier}-{occurredOn}` | `AnniversaryMilestone.id` verbatim (true date, incl. deferred acks) |
| streakMilestone | `streak-milestone-{count}-{occurredOn}` | crossing edge count + local civil day (same currency as `bestStreakAchievedOn`) |
| vacationReturn | `vacation-return-{startEpochSeconds}` | closed interval's start (synced log; end-reenter-end same date = two starts = two moments) |
| listReturn | `list-return-{listId}-{firedOn}` | Feature 4 event identity (ledger's `listId\|firedOn`), `sourceEventId = "listReturn:{listId}\|{firedOn}"` |

### 4.2 `MomentCopy.swift` — deterministic, no rotation

Racing writers must be content-identical → **one template per event shape, zero
rotation** (unlike every other Personal Layer deck). `copyDeckVersion` pinned; spelled
numbers from a fixed table (7 → "Seven", 30 → "Thirty", 50 → "Fifty"), numerals beyond.
Templates (all `{name}`-rendered via `PetCopyTemplate`):

- adoption (named): "You brought {name} home." · adoption (legacy/synthesized):
  "The day your story began."
- anniversary: week "One week together." / month "One month together." /
  year(n) "One year together." · "{n} years together."
- streakMilestone: "{Count} days in a row with {name}."
- vacationReturn: "You and {name} picked back up."
- listReturn: "You found your way back to {list}."

`accessibilityTextSnapshot` = rendered text + spoken date ("…, July 8, 2026").

### 4.3 `MomentFactory.swift` — pure payload derivation + `MomentRepository.swift`

`MomentFactory` is pure: `(event facts, petName?, locale, now) -> Moment`. Every
producer funnels through it so id ⇒ payload is a function (spec edge 3, asserted).

`FirestoreMomentRepository` (`users/{uid}/moments/{id}`):
- `moments(userId:) async throws -> [Moment]` — cache-friendly, ordered
  `occurredOn` desc. Full fetch v1 (bounded by account age; see §5 note).
- `ensureMoment(_:userId:)` — activityWeeks-style guard-then-set: cached
  `getDocument`; if absent, fire-and-forget `setData` (create-only rules reject a
  racing duplicate harmlessly; payloads are identical anyway). No transaction — unlike
  letters, the loser never needs the winner's content.

**Adoption atomicity**: new `UserProfileRepository.stampAdoption(adoptedOn:moment:userId:)`
writes the profile merge + the moment doc in **one `WriteBatch`** (fire-and-forget).
`PetIdentityStore.stampAdoption` calls it with:
- onboarding path (`completeNamingBeat`): named copy, `petNameSnapshot` = just-captured name;
- migration backfill path (`load`): legacy-neutral copy, `petNameSnapshot` nil.

**Synthesis fallback** (spec edge 2, and the entire existing install base): whenever
`JournalViewModel` loads with `profile.adoptedOn != nil` and no `adoption-…` moment in
the fetched set, it renders a deterministic synthesized row (legacy-neutral copy) *and*
enqueues `ensureMoment` — non-emptiness is structural, repair is idempotent.

### 4.4 Producers (exhaustive v1 — nothing else ever writes moments)

| Producer | Hook (exists) | New wiring |
|---|---|---|
| Adoption | `PetIdentityStore.stampAdoption` | batch API above |
| Streak milestone | `TaskCompletionStore.onMilestone` (`AppContainer:241`) | `MomentWriter.streakMilestone(count:)` alongside the CelebrationCenter post; name from `petIdentityStore.name`, date = today's civil day |
| Anniversary | `MemoriesService` detection (banner check + planner day-of) and `deferredAcknowledgment` | write on detection with the milestone's **true** `day` (deferred acks record their true date); id from `AnniversaryMilestone.id`; suppression rules do NOT gate the moment — the day happened even when the banner lost a collision |
| Vacation return | `VacationReentryService.finish`, after `vacationEnded(at:)` | moment from the just-closed interval (start = id, end date = `occurredOn`) |
| List return | where Feature 4 qualifies `.listReturn` for a surface (`ObservationService` evaluation path, ledger `Surface.journal`) | once per event via the ledger's existing `surfacedReturnEvents` currency; list name resolved + frozen at emission |

A small `MomentWriter` (`@MainActor`, injected via `AppContainer`) owns the
petName/locale/uid resolution so producers stay one-liners; all derivation stays in
the pure factory. Letters are **never** duplicated into moments — interleaved by
reference (§5).

### 4.5 Erasure + rules

- `AccountEraser.eraseAllData`: add `moments` beside letters/activityWeeks.
- `firestore.rules` — new block before the "future subcollections" comment, validating
  more than create-only (spec edge 19):

```
match /moments/{momentId} {
  allow read, delete: if isOwner(uid);
  allow update: if false;
  allow create: if isOwner(uid)
    && request.resource.data.type in
       ['adoption','anniversary','streakMilestone','vacationReturn','listReturn']
    && request.resource.data.schemaVersion == 1
    && request.resource.data.keys().hasAll(['type','occurredOn',
       'renderedTextSnapshot','accessibilityTextSnapshot',
       'localeIdentifier','copyDeckVersion','schemaVersion','createdAt'])
    && momentId.matches(prefixFor(request.resource.data.type) + '.*');
}
```

(`prefixFor` as a rules helper mapping the enum to id prefixes — `streakMilestone` →
`streak-milestone-` etc.) **Deploy is user-owned**; until deployed, server rejects
moment creates (client cache holds them) — same honest barrier Feature 3 hit.

## 5. New module: `MochiBuddy/Journal/`

`JournalView` / `JournalViewModel` / `JournalBehavior` / `JournalRouter` — house
pattern (`YouRouter` shape, shared `homeNavController`, route keys `journal.*`).

### 5.1 `JournalTimeline.swift` — the merge (pure, spec "Timeline composition")

- Row = `.letter(LetterRow)` | `.moment(MomentRow)`; sort key = **stored** dates:
  a letter dates by the calendar date of `periodEndExclusive` **in `letter.timeZoneId`**;
  a moment by `occurredOn` (date-only). Month groups from those stored dates — never
  the device zone (travel moves nothing; spec edge 16).
- Newest-first; same-day ties order **letters first**, then moments by natural id —
  deterministic on every device.
- Hero = newest unread letter, **excluded from the rows while promoted**; older unread
  rows keep an unread trait; read returns it to its chronological row (edges 6–7).
  Envelope clearing stays `LetterCompositionService.refreshUnread` — untouched.
- v1 fetches both collections fully (52 letters/yr + a few dozen moments) and merges
  purely; the composer takes `[Letter] + [Moment]` so month-bounded paging (two bounded
  queries per month page, no cross-collection cursor) can slot in later without
  re-architecture. Recorded as a deliberate v1 simplification.

### 5.2 States (spec table + design 1a–1d)

| State | Condition | Renders |
|---|---|---|
| Young | no letters and no non-adoption moments | centered pet + "Day one" eyebrow + adoption row + `AdoptedOnDate.displayString` + the forward-looking line "After your first full week together, Sunday letters will collect here." No charts, no observation card. |
| Growing | anything else exists | content order; **absent sections omitted, never placeholdered** |
| Rich | same rule — month grouping carries the scroll | full order incl. footer |

Header: eyebrow "JOURNAL", title = **full localized format string** "%@'s Journal"
(never possessive concatenation), live `petIdentityStore.name` (renames update the
header + card title live; artifacts keep snapshots — edge 11). Subtitle "With {name}
since {month}" except young state.

### 5.3 Observation card

"{Name} has noticed" — consumes `ObservationService` qualified set evaluated at
`effectiveNow`; ledger `Surface.journal` currencies apply; card omitted entirely when
the set is empty (edge 12). This is the first production caller of `observation_shown`.

### 5.4 Data footer (record, never grade)

Moves from Stats: `weekCells` (strip) + `trendPoints` (4-week Swift Charts trend) +
done-this-week + best streak (profile fields). **Dropped with recorded reasons**:
on-time % (a rate is a grade), busiest-weekday caption (ungated — Feature 4's job),
coins (currency state, lives on Home), per-list breakdown (the spec's footer content
list is exhaustive). Staging: footer omitted when the strip window has zero completions
(edge 13); the trend row renders only when the 4-week window spans ≥ 2 distinct weeks
(a one-week trend is noise — design's light/full split, pinned deterministically);
best streak joins with the trend row. Lapsed footer title: "The week you paused".

### 5.5 Lapse freeze (edge 14–15)

`effectiveNow = profile.observationIntervals.openInterval(.lapse)?.start ?? now` —
one value threaded through strip/trend/done derivations and the observation
evaluation. No decay-to-zero, no live drift; zero come-back copy anywhere; visual
desaturation + tired pet per the mock. Reactivation: the open lapse interval closes
(existing Feature 4 wiring) → derivations resume live over full retained history
including lapse-period completions. Best-streak display: verify at implementation
whether rewards advance during lapse; if they do, the tile pins to the profile values
whose `bestStreakAchievedOn ≤ lapseStart`, else current (resolve in §10).

### 5.6 Navigation migration (edge 18)

- `MainTab`: 4th case `journal` (icon `book.fill`, label "Journal" — static, never
  user content), inserted between tasks and you; `-mochiStartTab journal` works via
  `rawValue`.
- New `@Observable TabCoordinator` (AppContainer-owned): `selected: MainTab` +
  `pendingLetterRoute: String?`. `MainTabView` binds selection to it (replaces local
  `@State`). Letter-notification taps (`AppContainer.onLetterTap`) and the Home
  envelope tap now set `coordinator.openLetterInJournal(id)` → tab switches, Journal
  resolves the id via `letterService.letter(id:)` and pushes `LetterDetailView`
  (existing stable ids; `HomeViewModel`'s sheet consumption of
  `pendingNotificationOpen` retires). The Home envelope itself stays on Home.
- You tab sheds: Stats row + "Mochi's letters" row, `statsTapped`/`lettersTapped`
  actions, `showStats`/`showLetters` events, `navigateToStats`/`navigateToLetters`
  (letter detail push moves to `JournalRouting`). DEBUG scheduler row unaffected
  (edge 21).
- Stats module: `StatsView/ViewModel/Behavior` + tests deleted; strip/trend
  derivations live on in `JournalViewModel` (ported, attributed).

### 5.7 Instrumentation (os_log, no payloads)

`journal_opened` {source: tab | envelope | notification}; section impressions
(timeline / observations / data) **viewport-defined**: once per Journal session when
~half the section is visible (`onScrollVisibilityChange(threshold: 0.5)`), never at
construction. No new anti-churn event (correlation-not-proof note stands).

## 6. Remote Config

None. `RemoteTuningTests` count pin stays 74 — itself the proof of "zero keys".

## 7. Test plan (spec "Test coverage (required)" mapped)

- **Timeline merge**: stored-zone dating (a letter composed in Tokyo stays in its
  month under a New York device zone), month grouping, same-day tie (letter first,
  then moment id order), determinism (shuffled input, same output), hero exclusion.
- **Hero lifecycle**: promotion/read-return, multi-unread traits, envelope clears only
  at zero unread (via `LetterCompositionService` stub).
- **Moment identity**: full natural-key table; repeat 30-day streak = two moments;
  same-date vacation intervals = two moments; factory purity: same facts ⇒ identical
  payload (edge 3).
- **Adoption**: batch contains both writes (capturing stub); synthesis renders +
  enqueues idempotently; repair on second load writes nothing new; legacy copy contains
  no pet name; onboarding copy contains the captured name.
- **Backfill**: adoption only — no other moment producer fires from history replay.
- **Snapshots**: list-return renders after list rename/delete; locale change leaves
  stored prose untouched; rename updates header/card title, not artifacts.
- **States**: young/growing/rich; absent-section omission; **forbidden-output
  assertions**: no coins, no on-time %, no busiest-weekday anywhere in
  `JournalBehavior.UIState`.
- **Lapse freeze**: strip/trend/counts/observation set identical before and after
  completing tasks during lapse with `effectiveNow` pinned; reactivation includes
  lapse-period completions.
- **Navigation migration**: `MainTab.allCases` count/order; You state exposes no
  stats/letters rows; coordinator routes notification + envelope opens into Journal.
- **Accessibility**: timeline rows expose labels; hero announces unread; moment rows
  expose **no button traits**; month headers are headers.
- **Rules**: documented manual checks (no emulator harness, the standing gap):
  update rejected, wrong-prefix create rejected, foreign type rejected.

## 8. External setup produced by this feature (user-owned)

- **Deploy `firestore.rules`** (moments block) — until then, moment creates are
  server-rejected and live only in the local cache.
- No Remote Config work. No ASC work.

## 9. Out of scope (spec "Deferred")

Moment detail views, "All letters" filter, moment sharing, lifetime-coins record,
search/year-in-review, any Journal notification (destination, never a voice).

## 10. As-built deltas (implementation notes, July 25 2026)

- **The lapse guard in `TaskCompletionStore` (line ~75) makes the best-streak freeze
  structural**: lapsed completions earn nothing (coins/streak frozen, no spawns), so
  the streak can never advance during lapse, `onMilestone` can never fire, and the
  footer shows profile values with no special pinning. The §5.5 open question
  resolved itself; `MomentWriter`'s lapse gate is belt-and-suspenders.
- **Anniversary moment producers are two, not three**: day-of detection in
  `MemoriesService.checkAnniversaryBanner` (written BEFORE dedup/collision
  suppression - the day happened even when the banner lost), and vacation re-entry
  in `VacationReentryService.finish` via `MomentWriter.vacationEnded` (return moment
  + deferrable anniversaries the trip covered, true dates, re-entry day excluded).
  An anniversary that passes while the app is never opened that day dies quietly -
  deliberately aligned with Feature 2's banner rule; no backfill invents it later.
- **List-return moments write from `MemoriesService.assignPersonalLayer`** (the
  layer's most reliable evaluation beat, already lapse-gated) rather than a Journal
  or letter surface; once-per-event is the natural key itself, not the ledger.
- **Vacation-return identity** is the interval start's epoch seconds
  (`vacation-return-{Int(start.timeIntervalSince1970)}`) - the synced log carries
  no id field; a legacy vacation with no `vacationStartedAt` writes no moment.
- **`stampAdoptedOn` became `stampAdoption(_:moment:userId:)`** across the protocol,
  Firestore impl (one `WriteBatch`), caching wrapper, and test stub; the archive's
  `weekLabel` moved to `JournalTimeline` (the detail header still uses it).
- **The letter archive screen is deleted, not orphaned** (`LetterArchiveView` /
  `ViewModel` / `Behavior`): its row derivation lives on as the Journal's letter
  row; the "All letters" affordance would rebuild from the Journal components.
  `HomeRouter.letterDetail` and `HomeBehavior.PresentedLetter` retired with the
  envelope reroute; `LetterCompositionService.pendingNotificationOpen` deleted -
  `TabCoordinator.pendingLetterRoute` is the one notification/envelope handoff.
- **Observation card cadence**: live loads surface via Feature 4's
  `surfaced(.journal)` once per (conclusion, day) per VM session (a VM-local cache
  keeps the phrasing stable across tab visits); lapsed loads render through a new
  non-mutating `ObservationLedger.peekLine` so a read-only frozen surface never
  rotates the deck or logs `observation_shown`. Card caps at 3 lines.
- **`journal_opened` logs from `TabCoordinator`** (selection edge + routed opens),
  not the view - pop-backs from the letter detail can't inflate it.
- **Timeline pagination**: v1 fetches both collections fully and merges purely
  (bounded by account age; ~52 letters/yr); the composer takes plain arrays so
  month-bounded paging can slot in without re-architecture.
- **Trend staging rule pinned**: the 4-week trend renders once the (capped) stats
  span ≥ 2 distinct civil weeks; the best-streak tile joins the footer whenever
  the record is > 0. The strip + done count follow spec edge 13 exactly.
- Synthesis repair runs inline in `JournalViewModel.load` (awaited, testable)
  rather than fire-and-forget.

## 11. External setup checklist produced by this feature

- [ ] **Deploy `firestore.rules`** (new moments block). Until deployed, moment
  creates are server-rejected (client cache holds them) and the write-once
  adoption date still holds from Feature 1's deployed rules.
- [ ] No Remote Config, ASC, or RevenueCat work.
