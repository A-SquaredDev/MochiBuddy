# Mochi Journal · Reference

> A dictionary of everything the Journal tab can show: every entry type, every
> trigger, every string, every gate. Compiled from the shipped Feature 6 code
> (2026-07-27). Source of truth is always the code; file pointers are given per
> section so this doc can be re-verified.
>
> Sources: `MochiBuddy/Journal/` (View, ViewModel, Behavior, Timeline),
> `MochiBuddy/Moments/` (Moment, MomentCopy, MomentFactory, MomentWriter,
> MomentRepository), `MochiBuddy/Observations/ObservationCopy.swift`,
> `MochiBuddy/Letters/` for letter artifacts.

---

## 1. What the Journal is

The Journal is deliberately **a container, not an engine**: it renders artifacts
the other features already produced. Two kinds of entries are durable records
(**moments** and **letters**); two sections are derived live on every visit
(the **"has noticed" card** and the **record footer**). Absent sections are
omitted entirely, never placeholdered.

The governing doctrine is **record vs. grade**: the Journal records activity and
never judges it. No coins, no on-time percentage, no busiest-weekday. (Those
live on Streaks & stats, which the user explicitly chose to keep as a separate,
grade-permitted surface.)

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
| `With {name} since {Month}` / `With {name} since {Month Year}` | subtitle; adoptedOn known, not lapsed. Month drops the year inside the current year |
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
| `NEW LETTER · THIS WEEK` | uppercase chip with an accent dot |
| `"{excerpt}"` | first non-empty line of the letter body, quoted, 3-line limit |
| `From {name}` | byline |
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
| `"{excerpt}"` | first non-empty body line, 2-line limit |
| `From {name}` | byline |
| `Unread` / `Read` | trailing status capsule |
| a11y: `{date}, unread letter. {excerpt}` / `{date}, letter. {excerpt}` | |

Letter *content* is composed by Feature 3 (LetterComposer) and out of scope
here - the Journal renders it by reference and never rewrites it.

### 3b. Moment rows

Noninteractive by design (tapping does nothing in v1). Layout: icon tile +
rendered text + date label. a11y label = the text, value = the date; the stored
`accessibilityTextSnapshot` additionally appends the spoken date
(`"{rendered} {Month day, year}."`) so rows are self-contained.

---

## 4. Moment dictionary (the durable records)

Moments are **create-only, frozen-at-write** documents. The natural id
identifies an *event*, never merely a category - a rebuilt 30-day streak on a
later date is a new moment; two vacations ending on one date are two moments.
Copy is rendered once at write time from a **zero-rotation deck**
(`MomentCopy.deckVersion = 1`): racing writers deriving the same id must
produce byte-identical prose. Nothing composes while lapsed (except the
adoption synthesis repair, which records an existing fact).

| Type | Natural id | Trigger | `occurredOn` | Icon (placeholder SF Symbol) |
|---|---|---|---|---|
| adoption | `adoption-{adoptedOn}` | onboarding naming beat (batched with the `adoptedOn` write); or synthesized on Journal load when `adoptedOn` exists with no document | the adoption date | `heart.fill` (origin dot) |
| anniversary | `anniversary-{tier}-{date}` (milestone's own id) | day-of detection on Home's anniversary check, written even when a streak milestone owns the banner; month+ tiers covered by a vacation are written at re-entry on their TRUE date | the mark's own day | `sparkles` |
| streakMilestone | `streak-milestone-{count}-{day}` | the completion that crosses a sparse milestone (7, 30, then every 50 - `StreakMilestones`, RC-tunable) via `TaskCompletionStore.onMilestone` | device-local civil day of the crossing completion | `flame.fill` |
| vacationReturn | `vacation-return-{intervalStart epoch}` | vacation re-entry (`VacationReentryService.finish`), keyed by the synced interval start so end-reenter-end on one date is two moments | the trip's true end date | `sun.max.fill` |
| listReturn | `list-return-{listId}-{firedOn}` | a qualified Feature 4 list-return event, written from `assignPersonalLayer`; once-per-event via the id itself | the civil day the return fired (`stableSince`) | `arrow.uturn.backward` |

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

### 4b. Stored schema (Firestore `users/{uid}/moments/{id}`, schemaVersion 1)

`id` (natural key) · `type` · `occurredOn` (YYYY-MM-DD, rendered verbatim) ·
`renderedTextSnapshot` · `accessibilityTextSnapshot` · `petNameSnapshot`
(nil when unknowable) · `subjectNameSnapshot` (e.g. the list's name as of the
event) · `localeIdentifier` · `copyDeckVersion` · `sourceEventId` (provenance
link, e.g. `listReturn:{listId}|{firedOn}`) · `createdAt`.

Security rules (deploy pending as of this writing): owner-only; **create-only**
(no updates ever); creates validate schemaVersion, required fields, a type
enum, and that the id prefix matches the declared type. Delete stays open for
account erasure only.

---

## 5. "{name} has noticed" - the observation card

**Not stored entries.** Lines are derived live from the observation engine
(Feature 4) on every load and can appear, change phrasing, or retire as the
evidence shifts. At most **3** lines show (the engine's qualified order); an
empty set removes the card entirely. Each line renders with a `sparkle` glyph;
the card header shows a tiny pet face (sleeping while lapsed).

Surfacing bookkeeping: live lines route through `observation_shown` telemetry
and keep **one stable phrasing per (conclusion, day)** - revisiting the tab the
same day never rotates the deck. While lapsed, lines render through the
non-rotating `peekLine` at the frozen instant: verbatim, nothing advances.

### 5a. Qualification gates (all Remote Config tunable, `obs_*` keys)

Common ground: a 42-day evidence window, at most 3 contributions per day per
key (`obs_day_cap`), vacation/lapse days excluded, and conclusions must survive
a 14-day deterministic stability replay before they may speak.

| Kind | Concludes | Key gates (shipped defaults) |
|---|---|---|
| weekday | your most productive weekday | one-off tasks only (a weekly chore can't mint it); ≥15 completions across ≥3 distinct weeks; top day ≥30% share; margin gate vs the runner-up |
| timeOfDay | your productive band (morning / afternoon / evening / night) | ≥20 completions across ≥5 dates and ≥3 weeks; top band ≥40% share; margin gate |
| momentumRising | pace is picking up | recent-half vs earlier-half ratio ≥1.3 with ≥10 completions in the recent half and a minimum absolute delta; **rising only** - a falling trend is silence, never a concerned line; 7-day cooldown |
| listReturn | you came back to a neglected list | a list quiet ≥14 days with ≥5 prior completions moves again; event-typed (fires once per return) |
| comeback | slipped tasks get caught fast | ≥8 late-then-completed tasks across ≥3 dates and ≥3 distinct tasks; median catch-up ≤24h past the overdue boundary AND p75 ≤48h |

### 5b. Copy pools (every line, verbatim)

Templates: `{name}` = pet name, `{weekday}` = plural weekday
(`Sundays`…`Saturdays`), `{list}` = list name. Rotation is FNV-1a-seeded per
pool key, persisted in the ledger - you never hear the same phrasing twice in a
row. Locked rules: **qualitative only - no counts, no numbers, ever**; night
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
(rundown notifications, letters, and Stats' read-only peek) - this table is the
Journal's surface only. A qualified list-return additionally mints the durable
`list-return` moment (§4).

---

## 6. The record footer

Shown only once the last-7-days window holds at least one completion. Activity
without judgment - deliberately **no** coins, on-time %, or busiest-weekday.

| String | When |
|---|---|
| `THIS WEEK` | footer title, live |
| `The week you paused` | footer title while lapsed |
| week strip | 7 narrow day letters (`M T W…`) with count-scaled bars, a11y `{letter}: {n} tasks done` |
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
  write. This is why the timeline is structurally never empty for an adopted
  account - even while the moments rules block server writes.
- **Racing writers (edge 3):** create-only + one-canonical-payload means the
  losing writer's document would have been content-identical; no arbitration
  needed.
- **Deferred anniversaries:** marks covered by a vacation are written at
  re-entry on their true dates - except a mark landing on the re-entry day
  itself, which surfaces normally rather than as a memory.
- **Deep links:** Home's envelope and a letter notification route through the
  TabCoordinator into the Journal, which resolves the stable letter id and
  pushes the detail.

---

## 9. Telemetry (names only - no payloads, no conclusions)

- `journal_opened source=tab|…`
- `journal_section_impression section=timeline|observations|data` (once per
  section per Journal session)
- `observation_shown type={kind} surface=journal confidence=qualified` (the
  observation card's surfacing event)
- letter opens log through the letter system (`source=archive|home|notification`)

---

## 10. Copy rules that govern every string above (locked)

1. No em dashes, no UI emojis (SF Symbols only) - `mochi-copy-style`.
2. Observation lines are qualitative: no counts, no numbers, no percentages.
3. Attention, not measurement: "{name} noticed", never "your average".
4. Never scold: falling trends are silence; night rhythms are affirmed;
   list-return celebrates the return, never the absence; comeback praises the
   recovery, never mentions the slipping as a fault.
5. Moments are postcards: prose is frozen at write time in its original
   language and names, and never rewritten - not by renames, not by copy-deck
   updates (`copyDeckVersion` records which deck wrote it).
6. Records vs. grades: the Journal records; Streaks & stats may grade.
