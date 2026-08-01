# Mochi Journal · Reference

> A dictionary of everything the Journal tab can show: every entry type, every
> trigger, every string, every gate. Compiled from the shipped Feature 6 code
> (2026-07-27), re-verified against the code on 2026-08-01. Source of truth is
> always the code; file pointers are given per section so this doc can be
> re-verified.
>
> Sources: `MochiBuddy/Journal/` (View, ViewModel, Behavior, Timeline),
> `MochiBuddy/Moments/` (Moment, MomentCopy, MomentFactory, MomentWriter,
> MomentRepository), `MochiBuddy/Observations/` (Engine, Ledger, Service,
> Constants, Copy), `MochiBuddy/Letters/` (CompositionService, Period,
> Composer, Copy, PeriodSummaryBuilder, Repository),
> `MochiBuddy/Memories/` (AnniversaryCalendar, MemoriesService),
> `MochiBuddy/You/Vacation/VacationReentryService.swift`, `firestore.rules`.

---

## 1. What the Journal is

The Journal is deliberately **a container, not an engine**: it renders artifacts
the other features already produced. Two kinds of entries are durable records
(**moments** and **letters**); two sections are derived live on every visit
(the **"has noticed" card** and the **record footer**). Absent sections are
omitted entirely, never placeholdered.

The governing doctrine is **record vs. grade**: the Journal records activity and
never judges it. No coins, no on-time percentage, no busiest-weekday. (Those
were deleted with the retired Stats module; a test walks the UIState/Footer
field names to keep them out.)

---

## 2. Screen anatomy, top to bottom

| Section | Shown when | Source |
|---|---|---|
| Header | always | `JournalView.header` |
| Young state (day one) | no letters, no non-adoption moments, no completions this week | `youngState` |
| Hero letter | newest unread letter exists | `heroCard` |
| Story timeline | any letters/moments (grown state) | `timeline` |
| "{name} has noticed" card | ≥1 qualified observation | `noticedCard` |
| Record footer | ≥1 completion in the last 7 days | `footerCard` |

### 2a. Header strings

| String | When |
|---|---|
| `Journal` | eyebrow, always |
| `{name}'s Journal` | title, always |
| `With {name} since {Month}` / `With {name} since {Month Year}` | subtitle; adoptedOn known, not lapsed, grown state only (the day-one screen carries **no** since-line). Month drops the year inside the current year |
| `{name} is napping · paused` | subtitle while lapsed (plus a small sleeping, desaturated pet in the header) |

### 2b. Young state (day one)

Centered pet (content mood), then:

| String | Notes |
|---|---|
| `DAY ONE` | uppercase chip with a `sparkles` symbol |
| the adoption moment's rendered text | see §4 (adoption) |
| `July 23, 2026` | the stored adoption date, rendered verbatim |
| `After your first full week together, Sunday letters will collect here.` | forward-looking line; deliberately accurate to the letter gating (a day-one user does not get the upcoming Sunday's letter) |

### 2c. Hero letter (newest unread, promoted)

A presentation state of a timeline row, never a second copy - it is excluded
from the timeline below while promoted. Older unread letters stay in the
timeline with their unread badge.

| String | Notes |
|---|---|
| `NEW LETTER · THIS WEEK` | uppercase chip with an accent dot. Static text: it does not verify recency, so a returning user whose newest unread letter is older than a week still reads "this week" (`JournalView.swift:157`) |
| `"{excerpt}"` | first non-empty line of the letter body, quoted, 3-line limit |
| `From {name}` | byline (live pet name, not the letter's snapshot) |
| `Read letter` | the button capsule |
| a11y: `New unread letter from {name}. {excerpt}` + hint `Opens the letter` | |

---

## 3. The story timeline

A merge of letters and moments, **newest first**, grouped by month.

**Dating rules (pinned):**
- A letter dates by the calendar date of its `periodEndExclusive` **in the zone
  stored on that letter** (the postcard rule - a date never shifts with the
  reader's travels).
- A moment dates by its date-only `occurredOn` (YYYY-MM-DD), rendered verbatim
  through a fixed UTC calendar. Stored dates are civil facts, never
  zone-shifted; travel cannot move old artifacts between months.
- Same-day ties: **letters before moments** (the richer artifact), then moments
  by natural id - deterministic on every device.

**Month headers:** `July` inside the current year, `July 2025` outside it.

**Rail:** every row hangs off a dot rail. Letters and the adoption moment get
the filled "origin" dot; all other moments get the hollow dot.

### 3a. Letter rows

| String | Notes |
|---|---|
| `SUNDAY LETTER` | uppercase chip; `envelope.badge.fill` when unread, `envelope.fill` when read |
| `Jul 18` | date label from the stored date |
| `"{excerpt}"` | first non-empty body line (of the private variant), 2-line limit |
| `From {name}` | byline |
| `Unread` / `Read` | trailing status capsule |
| a11y: `{date}, unread letter. {excerpt}` / `{date}, letter. {excerpt}` | |

Letter *content* is composed by Feature 3 - the Journal renders it by reference
and never rewrites it. The full composition contract is §3c.

### 3b. Moment rows

Noninteractive by design (tapping does nothing in v1). Layout: icon tile +
rendered text + date label. a11y label = the text, value = the date; the stored
`accessibilityTextSnapshot` additionally appends the spoken date
(`"{rendered} {Month day, year}."`) so rows are self-contained.

### 3c. The letter artifact, end to end (`MochiBuddy/Letters/`)

The letter is the Journal's richest entry: an immutable postcard for a closed
week, composed exactly once, then rendered by reference forever. `readAt` is
its one mutable field (synced, so a letter read on the phone doesn't re-flag on
the iPad).

**The period (`LetterPeriod.swift`).** Monday 00:00 through the *effective send
instant* on the send day - `letter_send_weekday` (default 1 = Sunday) at
`letter_send_hour` (default 19:00), pulled *earlier only* when the send hour
falls inside the bedtime window (the clamp moves the cutoff too; they are one
instant). The period end IS the cutoff: a completion at Sunday 20:30 belongs to
the next period by definition. All boundary math runs in the **authoritative
zone** - the synced profile timezone, never whichever zone the device is in -
so two devices always identify the same period. Identity is the Monday as a
plain date, `letter-2026-07-20` (deliberately not an ISO week id; calendar year
and week-based year diverge around New Year). The attribution window a letter
owns runs from the *previous* period's cutoff to its own cutoff, so the Sunday
evening tail of each week belongs to the next letter.

**When a letter is generated (`LetterCompositionService.composeIfDue`).** Only
on user-visible foregrounds (home entry, scene activation, notification tap -
wired in `RootView`; never background refresh or widget drains). The previous
closed period composes iff every gate passes:

1. **Not lapsed, not on vacation.** A period that closed just before a trip
   composes late, on the first post-vacation foreground. Lapse means no
   letters and **no backfill on return**.
2. **First-period gate:** the candidate must start on or after the first FULL
   post-adoption period (`firstEligiblePeriodStart` = the Monday after the
   adoption week). The adoption week's partial period never composes; day-one
   delight is carried in-app.
3. **Not already composed:** cheap cache check, then a server check behind the
   barrier.
4. **Non-dormant:** at least one completion inside the attribution window OR a
   user-visible foreground during the period, attested by the create-only
   `activityWeeks/{periodId}` marker (stamped at most once per period per
   launch on foreground). Dormant weeks skip silently - never backfilled,
   never "we missed you".
5. **Not fully vacation-covered:** a period whose whole window sits inside a
   vacation interval composes nothing, ever. Partial overlap composes the
   vacation-partial letter.

**The online barrier.** Composition is the app's one deliberate exception to
fire-and-forget: flush pending writes, re-read profile/archive/stats
server-backed (re-deriving the period from the SERVER zone), compose purely,
then create inside a transaction with an existence precondition
(`createLetterIfAbsent`). If two devices race, the first composer wins; the
loser discards its local result and displays the winner. Any barrier failure
means "try again next foreground" - late is acceptable, wrong is not. The
letter notification is only ever an invitation, planned only once the current
period is already non-dormant (`plannedLetterInput`), firing at the cutoff; the
letter becomes available on the next eligible foreground regardless.

**Classification (`LetterClassifier`, thresholds RC-tunable via `letter_*`
keys, baked into the stored letter at compose time).** Precedence:
`vacationPartial` > `rough` > `great` > `quiet` > `steady`.

| Class | Condition (shipped defaults) |
|---|---|
| vacationPartial | any vacation interval overlaps the window |
| rough | ≥4 window days with an overdue task sitting (`letter_rough_overdue_days`), OR completions < 0.25 x trailing average with ≥1 due task |
| great | completions ≥ 1.5 x trailing average (`letter_great_ratio`) AND ≤1 overdue day |
| quiet | completions ≤ 2 (`letter_quiet_max`) AND tasks due ≤ 2 |
| steady | everything else |

The trailing average is the mean over up to 4 prior attribution windows that
postdate the first eligible period; nil with no usable history, so a brand-new
user can be neither "great" nor ratio-"rough".

**Beat selection (`LetterComposer`).** Two-phase. The class's structural beat
goes first and is never displaced; optional beats fill remaining slots by
priority, one per category, at most `letter_max_beats` (3) beats total:

- **quiet:** the single cozy quiet beat, nothing else - the shortest letter in
  the system, by design.
- **rough:** presence beat first; at most one small-true-positive iff
  `completionCount > 0`; nothing else may enter. The rough pools are
  structurally restricted: `{name}` is the only slot, no quantities, no task
  titles, no observations, no question marks (no ask). Rough letters never
  offer the full share variant.
- **vacationPartial:** the vacation beat, then optional fill up to the shared
  three-beat budget (two fill slots after the structural beat).
- **great / steady:** optional fill only; a steady week with no notable facts
  still gets one small-true-positive beat.

Optional priority: **milestone > comeback > bestDay > observation > list
return**, with at most ONE insight-family beat (observation XOR list return - a
three-beat letter must not contain two separate "Mochi analyzed you" moments).
The milestone beat carries streak milestones, an anniversary, or BOTH in one
collision beat (Feature 2's rule: the streak owned the banner that day; the
letter remembers both).

**Beat facts (`PeriodSummaryBuilder`):**

| Fact | Derivation |
|---|---|
| milestonesLanded | walk the unbroken active-day chain back from `lastActiveDate` with the current streak count; collect counts passing `StreakMilestones.isMilestone` whose day falls in the window; a broken chain stops the walk (never guess) |
| anniversary | `AnniversaryCalendar.milestones` over the window's civil days; the last (largest/latest) mark wins; `duringVacation` flags a mark whose date a trip covered and switches the copy pool |
| comeback | the single longest-waiting overdue task cleared inside the window (title interpolated in the full variant only; the private variant is neutral by template, never string surgery) |
| bestDay | the window's max completions on one civil day, only if ≥3 |
| observationConclusion | the highest-priority qualified engine conclusion passing the same-week letter/rundown dedup and the momentum cooldown |
| listReturnName | a qualified list-return event's surviving list name (its own beat, insight family) |

**Randomness: none.** Line variety is a stable hash - FNV-1a over
`"{periodId}|{beatKey}"` indexes the pool, advancing past any line id used in
the previous two letters (`dontRepeatLastN` = 6 ids, drawn from
`archive.prefix(2).flatMap(\.lineIds)`). If every line in a tiny pool was
recent, repeating is the honest fallback. Composition is deterministic AND
device-independent with zero stored rotation state (never `String.hashValue`,
which is per-process randomized).

**Assembly.** Register-matched salutation + beats + register-matched closing +
the signature `From {name}` (from `petNameSnapshot`, forever - renames never
touch a written letter). Interpolation is per-beat: a best-day `{weekday}` and
a comeback `{weekday}` are different facts and never cross paragraphs. Both
share variants (`fullRenderedText`, `privateRenderedText`) are composed
together at creation.

**Template library (`LetterCopy`, deck version 2).** Pools and slots:

| Pool | Lines | Slots beyond {name} |
|---|---|---|
| standard / quiet / rough / vacation salutations | 3 each | none |
| milestonePool | 3 | `{milestone}` (spelled streak count) |
| anniversaryPool / anniversaryVacationPool | 3 each | `{annspan}` ("one week", "one month", "one year", "two years") |
| milestoneCollisionPool | 3 | `{milestone}` + `{annspan}` |
| comebackPool | 3 | `{task}` (full variant only) + `{weekday}` |
| bestDayPool | 3 | `{weekday}` + `{count}` (spelled) |
| observation pools (weekday / morning / afternoon / evening / night / momentum / comeback) | 2 each | `{weekday}` only in the weekday pool |
| listReturnPool | 2 | `{list}` |
| presencePool / smallTruePositivePool / quietPool | 3 each | none |
| standard / quiet / rough closings | 3 each | none |

**Frequency rules.** At most one letter per period, ever (create-only
transaction; the rules leave only `readAt` mutable). No letter for the adoption
week, dormant weeks, fully-covered vacation weeks, or lapse weeks - those gaps
are permanent, not queued. Late composition is fine; the letter still carries
its own period's dates and zone.

**Edge cases worth knowing.**
- Bedtime clamp: a quiet window covering Sunday 19:00 pulls the send AND the
  cutoff earlier that day, never later.
- Zone changes: the marker, period identity, and window all derive from the
  synced profile zone, so a phone and iPad near a boundary agree.
- After a winning create, the observation the letter used is recorded as
  surfaced (same-week letter/rundown dedup) and a notification re-lay is
  requested. See §11 for two asymmetries in this bookkeeping.
- DEBUG builds ship `debugForceCompose`, which skips the gates but not the
  once-only existence contract.

**Storage** (`users/{uid}/letters/{letter-YYYY-MM-DD}`): periodStart,
periodEndExclusive, timeZone, classification, beatTypes, lineIds, both rendered
texts, petNameSnapshot, composedAt, composerVersion, copyDeckVersion,
periodSummaryHash (non-reversible provenance), readAt. Rules: create and delete
owner-only; updates may touch `readAt` and nothing else.

---

## 4. Moment dictionary (the durable records)

Moments are **create-only, frozen-at-write** documents. The natural id
identifies an *event*, never merely a category - a rebuilt 30-day streak on a
later date is a new moment; two vacations ending on one date are two moments.
Copy is rendered once at write time from a **zero-rotation deck**
(`MomentCopy.deckVersion = 1`): racing writers deriving the same id must
produce byte-identical prose. Nothing composes while lapsed (`MomentWriter`
resolves a nil userId) - except the adoption synthesis repair, which records an
existing fact.

| Type | Natural id | Trigger | `occurredOn` | Glyph (asset catalog) |
|---|---|---|---|---|
| adoption | `adoption-{adoptedOn}` | onboarding naming beat, batched atomically with the `adoptedOn` write (`PetIdentityStore.stampAdoption`); the legacy backfill path; or synthesized on Journal load when `adoptedOn` exists with no document | the adoption date | `moment-adoption` (origin dot) |
| anniversary | `anniversary-{tier}-{date}` (milestone's own id) | day-of detection in `MemoriesService.checkAnniversaryBanner` (Home's first-open check), written even when a streak milestone owns the banner; month+ tiers covered by a vacation are written at re-entry on their TRUE date | the mark's own day | `moment-anniversary` |
| streakMilestone | `streak-milestone-{count}-{day}` | the completion that crosses a sparse milestone (7, 30, then every 50 after 30 - `StreakMilestones`, RC-tunable) via `TaskCompletionStore.onMilestone`; only the completion that extends the streak fires it | device-local civil day of the crossing completion | `moment-streak` |
| vacationReturn | `vacation-return-{intervalStart epoch}` | vacation re-entry (`VacationReentryService.finish` - by date, by cap, or by hand), keyed by the synced interval start so end-reenter-end on one date is two moments | the trip's true end date, `min(scheduledEnd, now)` | `moment-vacation` |
| listReturn | `list-return-{listId}-{firedOn}` | a qualified Feature 4 list-return event, written from `MemoriesService.assignPersonalLayer` on every notification re-lay (the ledger's surfacing cadence is NOT consulted - the event happened); once-per-event via the id itself | the civil day the return fired (`stableSince`) | `moment-list-return` |

The glyph column changed with roadmap #6: the commissioned moment glyphs now
ship in the asset catalog (`JournalTimeline.icon(for:)`), rendered as template
images tinted at the render site. The old SF Symbol placeholders are gone.

### 4a. Moment copy (every string)

| Event | String |
|---|---|
| Adoption (name known) | `You brought {name} home.` |
| Adoption (backfilled/synthesized - the name on that day is unknowable) | `The day your story began.` |
| Anniversary · week | `One week together.` |
| Anniversary · month | `One month together.` |
| Anniversary · year 1 | `One year together.` |
| Anniversary · year N | `{N} years together.` (spelled out through ten: `Two years together.`) |
| Streak milestone | `{count} days in a row with {name}.` - count spelled for 1-10, 30, 50, 100 (`Seven days in a row with Nori.`); numerals otherwise |
| Vacation return | `You and {name} picked back up.` |
| List return | `You found your way back to {list}.` - the list name is frozen as of the event; a later rename or delete never rewrites the timeline |
| Accessibility variant (all types) | `{rendered} {spoken date}.` |

Anniversary copy is deliberately **name-free** so the payload cannot drift
under an in-flight rename. `AnniversaryTier.deferrable`: month and year marks
earn the vacation-deferred write; the 1-week mark is too small to backdate.
Anniversary math is calendar-clamped like the platform clamps (adoption Jan 31
puts the month mark on Feb 28/29; adoption Feb 29 puts the yearly mark on
Feb 28 in non-leap years) and deliberately not remote-tunable.

### 4b. Stored schema (Firestore `users/{uid}/moments/{id}`, schemaVersion 1)

`id` (natural key) · `type` · `occurredOn` (YYYY-MM-DD, rendered verbatim) ·
`renderedTextSnapshot` · `accessibilityTextSnapshot` · `petNameSnapshot`
(nil when unknowable) · `subjectNameSnapshot` (e.g. the list's name as of the
event) · `localeIdentifier` · `copyDeckVersion` · `sourceEventId` (provenance
link, e.g. `listReturn:{listId}|{firedOn}`) · `createdAt`.

Security rules (shipped in `firestore.rules`, deployed): owner-only;
**create-only** (no updates ever); creates validate schemaVersion, required
fields, a type enum, and that the id prefix matches the declared type. Delete
stays open for account erasure only.

`ensureMoment` is guard-then-set, fire-and-forget: the natural key makes
duplicates structurally impossible and payloads are deterministic, so no
transaction is needed - a racing loser's rejected write would have been
content-identical anyway.

---

## 5. "{name} has noticed" - the observation card

**Not stored entries.** Lines are derived live from the observation engine
(Feature 4) on every load and can appear, change phrasing, or retire as the
evidence shifts. At most **3** lines show (the engine's qualified order); an
empty set removes the card entirely. Each line renders with a `sparkle` glyph;
the card header shows a tiny pet face (sleeping while lapsed).

Surfacing bookkeeping: live lines route through `observation_shown` telemetry
and keep **one stable phrasing per (conclusion, day) per app session** - the
cache lives on the view model, so revisiting the tab the same day never rotates
the deck, but an app relaunch the same day draws (and records) a fresh line.
While lapsed, lines render through the non-rotating `peekLine` at the frozen
instant: verbatim, nothing advances, no cadence state is written.

### 5a. Qualification gates (all Remote Config tunable, `obs_*` keys)

Common ground: a 42-day evidence window (`obs_window_days`), vacation/lapse
days excluded where the type says so, and the **trait types** (weekday,
timeOfDay, comeback) must survive a deterministic 14-day stability replay
(`obs_sticky_days` over a 90-day replay depth) before they may speak - an
incumbent also needs 14 consecutive failing days to retire or be replaced.
Momentum and list return are NOT replayed: momentum is a compose-time fact
(qualifies now or not at all), list return is an event that fires, surfaces
within 7 days, then expires. The 3-per-day cap (`obs_day_cap`) applies to the
weekday and time-of-day distributions only - one bulk-cleanup burst cannot mint
a trait.

| Kind | Concludes | Key gates (shipped defaults) |
|---|---|---|
| weekday | your most productive weekday | one-off tasks only (a weekly chore can't mint it); ≥15 day-capped completions across ≥3 distinct weeks; top day ≥30% share; top ≥1.5x the runner-up (an unopposed top passes; a tie fails) |
| timeOfDay | your productive band (morning / afternoon / evening / night) | all completions; ≥20 day-capped completions across ≥5 dates and ≥3 weeks; top band ≥40% share; 1.5x margin gate |
| momentumRising | pace is picking up | recent-half vs earlier-half per-eligible-day rate ≥1.3x with ≥10 completions in EACH half and an absolute delta ≥0.2/day; every window day's vacation/lapse eligibility must be known (pre-log days silence it); **rising only** - a falling trend is silence, never a concerned line; 7-day cooldown after surfacing anywhere |
| listReturn | you came back to a neglected list | a surviving list quiet ≥14 days with ≥5 completions up to the pre-gap completion moves again; the quiet spell must be clean (no vacation/lapse/pre-log days - absence must be behavior); event-typed, surfaces within 7 days of firing, latest return wins |
| comeback | slipped tasks get caught fast | ≥8 late-then-completed events across ≥3 dates and ≥3 distinct task identities; median catch-up ≤24h past the overdue boundary AND p75 ≤48h |

### 5b. Copy pools (every line, verbatim)

Templates: `{name}` = pet name, `{weekday}` = plural weekday
(`Sundays`…`Saturdays`), `{list}` = list name. Rotation is a persisted
round-robin cursor per pool key (`CopyDeck`, stored in the observation ledger,
keyed per Firebase UID) - you never hear the same phrasing twice until the pool
cycles. Locked rules: **qualitative only - no counts, no numbers, ever**; night
never implies the schedule is wrong; list-return never references the absence.
Ship test for every line: *would this make someone at the floor feel worse?*

**weekday** (`obs-weekday`)
- `You get the most done on {weekday}. {name} noticed.`
- `{weekday} are your days. {name} keeps notes on these things.`
- `Something about {weekday} suits you. {name} has been paying attention.`
- `{name} thinks of {weekday} as your day now.`

**morning** (`obs-morning`)
- `Mornings are when things happen around here. {name} noticed.`
- `You and mornings get along. {name} keeps notes.`
- `The early hours are yours. {name} has seen it enough to be sure.`
- `{name} noticed the day's wins tend to come early.`

**afternoon** (`obs-afternoon`)
- `Afternoons are when things happen around here. {name} noticed.`
- `You hit your stride after lunch. {name} keeps notes.`
- `The middle of the day is yours. {name} has seen it enough to be sure.`
- `{name} noticed the afternoon is where your day comes together.`

**evening** (`obs-evening`)
- `Evenings are when things happen around here. {name} noticed.`
- `You wind the day down by getting things done. {name} keeps notes.`
- `The evening is yours. {name} has seen it enough to be sure.`
- `{name} noticed your day comes together in the evening.`

**night** (`obs-night`) - affirms, never corrects
- `Things get done after 9pm around here, and that counts just the same. {name} noticed.`
- `The late hours are yours. {name} thinks that's a fine time for them.`
- `{name} noticed the quiet hours are when you get things done. No notes, just admiration.`
- `Night is when your list gets shorter. {name} keeps you company either way.`

**momentum** (`obs-momentum`)
- `More check-offs lately. {name} can feel it.`
- `Things are moving around here. {name} noticed.`
- `{name} can tell something's picked up lately.`
- `The list has been shrinking faster. {name} is quietly delighted.`

**list return** (`obs-list-return`)
- `You found your way back to {list} this week. {name} noticed.`
- `{list} got some attention this week. {name} was glad to see it.`
- `Back to {list} this week. {name} likes seeing that one move.`
- `{name} noticed {list} moving again this week.`

**comeback** (`obs-comeback`)
- `When something slips, you catch it fast. {name} loves that about you.`
- `{name} noticed you always circle back. It never takes you long.`
- `Slipped things don't stay slipped around you. {name} keeps notes.`
- `You have a way of catching things quickly. {name} admires it.`

Card header: `{name} has noticed`.

Note: the same conclusions feed other surfaces with their own pools and cadence
(rundown notifications, letter beats, and suggested times) - this table is the
Journal's surface only. Journal surfacing never counts against the same-week
letter/rundown dedup (only `lastSurfaced` advances; see §11 for the momentum
side effect). A qualified list-return additionally mints the durable
`list-return` moment (§4).

---

## 6. The record footer

Shown only once the last-7-days window holds at least one completion. Activity
without judgment - deliberately **no** coins, on-time %, or busiest-weekday.

| String | When |
|---|---|
| `THIS WEEK` | footer title, live |
| `The week you paused` | footer title while lapsed |
| week strip | 7 narrow day letters (`M T W…`) with count-scaled bars (full height at 6+/day), a11y `{letter}: {n} tasks done` |
| `LAST 4 WEEKS` | eyebrow over the 28-day trend chart - rendered only once history spans **≥2 distinct civil weeks** (a one-week "trend" is noise, not a record) |
| `{n}` + `Done this week` | count block, live |
| `{n}` + `Done that week` | count block while lapsed |
| `{n}` + `Best streak` | flame glyph; omitted entirely at zero |

---

## 7. Lapse behavior (the freeze)

While lapsed, **everything evaluates at `effectiveNow` = the open lapse
interval's start**. The record stops moving instead of decaying toward zero:

- completions logged after the pinned instant exist in the fetch but not the
  record (the week strip, trend, and counts are capped at the freeze);
- observation lines re-derive at the pinned instant and render via the
  non-rotating peek - frozen verbatim, nothing composes, nothing advances;
- moment writers no-op (except the adoption synthesis repair);
- the whole grown content renders at 72% saturation, the header pet sleeps,
  and the subtitle reads `{name} is napping · paused`;
- **zero come-back copy anywhere** - the Journal never sells reactivation.

On reactivation the interval closes and everything resumes live over full
retained history, lapse-period completions included.

---

## 8. Edge behaviors worth knowing

- **Adoption synthesis (edge 2):** if `adoptedOn` exists with no adoption
  document, the Journal renders a synthesized row immediately (legacy copy,
  since the name on that day is unknowable) and enqueues the idempotent repair
  write - deliberately allowed even while lapsed, since it records an existing
  fact. This is why the timeline is structurally never empty for an adopted
  account.
- **Racing writers (edge 3):** create-only + one-canonical-payload means the
  losing writer's document would have been content-identical; no arbitration
  needed.
- **Deferred anniversaries:** marks covered by a vacation are written at
  re-entry on their true dates - except a mark landing on the re-entry day
  itself, which surfaces normally rather than as a memory.
- **Missed anniversaries:** outside the vacation repair, an anniversary moment
  only mints if Home runs its day-of check on the mark's exact civil day. A
  mark that passes while the app is simply unopened (or during lapse) never
  becomes a moment; the weekly letter's anniversary beat is the only surface
  that can still remember it. See §11.
- **Deep links:** Home's envelope and a letter notification route through the
  TabCoordinator into the Journal, which resolves the stable letter id and
  pushes the detail (falling back to a service fetch when the archive hasn't
  loaded it yet).

---

## 9. Telemetry (names only - no payloads, no conclusions)

- `journal_opened source=tab|envelope|notification` (tab selection logs `tab`
  only when no letter route is pending)
- `journal_section_impression section=timeline|observations|data` (once per
  section per Journal session, at half-visible)
- `observation_shown type={kind} surface=journal confidence=qualified` (the
  observation card's surfacing event)
- letter opens log through the letter system (`source=archive|home|notification`,
  classification, time-to-open bucket, first-open flag); composition logs
  classification, beat types, and a word-count bucket

---

## 10. Copy rules that govern every string above (locked)

1. No em dashes, no UI emojis (SF Symbols only) - `mochi-copy-style`.
2. Observation lines are qualitative: no counts, no numbers, no percentages.
3. Attention, not measurement: "{name} noticed", never "your average".
4. Never scold: falling trends are silence; night rhythms are affirmed;
   list-return celebrates the return, never the absence; comeback praises the
   recovery, never mentions the slipping as a fault. Rough letters carry no
   digits, no titles, no asks - asserted structurally at the template level.
5. Moments and letters are postcards: prose is frozen at write time in its
   original language and names, and never rewritten - not by renames, not by
   copy-deck updates (`copyDeckVersion` records which deck wrote it).
6. Records vs. grades: the Journal records; nothing on this surface grades.

---

## 11. Known rough edges (verified against code, 2026-08-01)

Documented so re-verification doesn't mistake them for spec:

- **Same-day phrasing stability is per session:** the (conclusion, day) cache
  lives on the JournalViewModel; a relaunch re-rotates the deck the same day
  (`JournalViewModel.swift`). Momentum is the exception since the fix pass:
  on later visits of its surfacing day it renders via the non-rotating peek,
  which may show the NEXT line in rotation rather than the one first shown.

Fixed in the 2026-08-01 fix pass (roadmap step 4), kept here for history:

- **Vacation letter beat cap** (fixed): the composer now passes the full
  `maxBeats` budget for vacation-partial; `fillOptionalBeats` alone accounts
  for the structural beat, so vacation letters reach 3 beats like every other
  class. Pinned by `LetterComposerTests.vacationPartialFullBudget`.
- **Observation consumed but unheard** (fixed): the service records
  `summary.observationConclusion` as surfaced only when
  `composed.beatTypes.contains(.observation)` - a slot-starved compose no
  longer burns the conclusion's same-week dedup.
- **List-return letter beats never recorded** (fixed): a told `.listReturn`
  beat now records its qualified event (carried through
  `PeriodSummary.listReturnObservation`) under its real `listId|firedOn` key,
  so the event cannot resurface within its horizon.
- **Journal visits cooled momentum down everywhere** (fixed): the card now
  consults `momentumCoolingDown` before surfacing; on the surfacing day the
  line stays visible via the non-rotating peek, on later cooldown days
  momentum rests on the card like every other surface, and `lastSurfaced`
  stops advancing daily - rundowns and letters get momentum back once the
  window ends.
