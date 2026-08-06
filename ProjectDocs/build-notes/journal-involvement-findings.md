# Journal involvement findings

> Read-only investigation ahead of the "make the Journal feel more involved"
> planning pass. Every claim below was verified against code on 2026-08-02;
> citations are file:line as of this working tree. Where the spec docs
> (mochi-requirements.md, Mochi-journal.md) and the code disagree, the
> disagreement is recorded as a finding. No build order is proposed here.

Doctrine shorthand used throughout:
**D1** container, not engine · **D2** record vs. grade · **D3** record vs.
derive · **D4** never scold · **D5** determinism.

---

## 1. Verified / contradicted

### 1a. The four doctrine drifts

**Hero chip "NEW LETTER · THIS WEEK" is unconditional — CONFIRMED.**
The string is a literal at `JournalView.swift:157` with no recency input. The
hero is simply the newest unread letter: `letters.first(where: \.isUnread)`
(`JournalViewModel.swift:173`). A returning user whose newest unread letter is
five weeks old reads "this week". The spec documents this honestly
(`Mochi-journal.md` §2c "Static text: it does not verify recency").
*What the call site could condition on:* the view only receives
`HeroLetter(letterId, excerpt, dateLabel)` (`JournalBehavior.swift:20-24`), so
the view cannot fix it alone — but the view model's `load()` holds the full
`Letter` (`periodEndExclusive`, `timeZoneId`), `now`, `calendar`, and the
profile (bedtime, timezone) at `JournalViewModel.swift:173-180`. A truthful
chip is one derived field away: either compare `now` against
`letter.periodEndExclusive + 7d`, or reuse
`LetterSchedule.period(containing:)` (`LetterPeriod.swift:60-66`) to ask
whether the hero's period is the one that just closed. Alternatively the chip
could carry the date the row already computes (`hero.dateLabel`). Note the
accessibility label already omits the claim ("New unread letter from …",
`JournalView.swift:195`) — VoiceOver users get the honest version today.

**Footer "Best streak" reads as a target — CONFIRMED (as a tension, not a bug).**
Construction at `JournalView.swift:462-483`: the best-streak tile sits inside
the same HStack as the "Done this week" count, in the identical visual
grammar — same 22pt display font (`JournalView.swift:453` vs `:474`), same
muted caption treatment — separated only by a hairline. The one distinguishing
element is `flame.fill` (`JournalView.swift:470`), which is achievement
iconography, not record iconography; it makes the tile read *more* like a
score, not less. "Best" is a superlative ranking of your past against itself —
the only element on the surface that invites beating a number.
`JournalTests.swift:369-382` pins the absence of coins / on-time / busiest-
weekday but does not (and cannot) pin the register of this tile. The data is
`profile.bestStreakCount` passed straight through
(`JournalViewModel.swift:208-214`); omitted at zero. Whether a frozen personal
record is a "record" (D2-compliant) or a "target" (D2 violation) is a human
call — see §4.

**Anniversary minting has a day-of-or-never gap — CONFIRMED.**
Every producer of an anniversary moment, exhaustively:
1. `MemoriesService.checkAnniversaryBanner` (`MemoriesService.swift:300-343`),
   invoked from Home's first-open check (`HomeViewModel.swift:391`). It mints
   only when `AnniversaryCalendar.milestone(adoptedOn:on: today)` matches
   *today exactly* (`MemoriesService.swift:307-316`), and is guarded by
   `!membershipSession.isLapsed` and `!profile.vacationActive`
   (`MemoriesService.swift:301-305`). The write happens before banner dedup
   and streak-collision suppression, deliberately.
2. `MomentWriter.vacationEnded` (`MomentWriter.swift:75-100`), from
   `VacationReentryService.finish` (`VacationReentryService.swift:129`): mints
   deferrable (month+) marks the trip covered, each at its TRUE date.

There is **no third path**. A month+ mark that passes while the app is simply
unopened (no vacation interval covering it) is never minted; ditto marks
passing during lapse. `Mochi-journal.md` §8 "Missed anniversaries" documents
this accurately — spec and code agree; the gap is real.

*Bounded repair cost.* The shape already exists twice: adoption synthesis
(`JournalViewModel.swift:126-132` renders the missing row now and enqueues
`ensureAdoptionMoment`, which deliberately bypasses the lapse gate because it
records an existing fact — `MomentWriter.swift:121-131`), and the vacation
deferral (scan `AnniversaryCalendar.milestones` over a closed day range, mint
each deferrable mark at its true date — `MomentWriter.swift:90-99`). A repair
"mint if the mark passed within N days" is the same scan over
`[today − N, yesterday]` plus idempotent `ensureMoment` calls: pure date math
(`AnniversaryCalendar.milestones`, `AnniversaryCalendar.swift:102-113`), no
schema change (type `anniversary` already exists in `firestore.rules:80-81`),
no RC key, at most one or two writes per repair. Duplicate attempts are
structurally safe: the natural id `anniversary-{tier}-{date}`
(`AnniversaryCalendar.swift:44-52`) and name-free deterministic copy
(`MomentFactory.swift:40-54`) make racing/overlapping writers content-
identical, and creates are rejected free on collision
(`MomentRepository.swift:94-106`).
*What it collides with:*
- **The vacation-deferral ownership.** A repair window running while a
  vacation is open would front-run the "truly silent during the trip" rule.
  It must exclude marks whose date sits inside any vacation interval
  (available: `profile.observationIntervals`) and leave those to re-entry.
  Marks covered by an already-*closed* trip overlap harmlessly (same id, same
  payload).
- **The lapse gate.** `MomentWriter.anniversary` no-ops while lapsed
  (`MomentWriter.swift:42-45`). Repairing a lapse-covered mark needs an
  ungated path like `ensureAdoptionMoment`'s — whether that is "recording an
  existing fact" (the adoption-synthesis precedent) or backdated guilt (the
  Feature 2 stance, `MemoriesService.swift:12-14`) is a §4 decision.
- **The banner.** The repair must write the moment only — never post to
  `CelebrationCenter` and never touch `bannerShown`. Today's mark stays with
  the day-of path.

**Phrasing cache is view-model-scoped — CONFIRMED.**
`surfacedLines: [String: String]` lives on the view model
(`JournalViewModel.swift:43`), keyed `conclusionKey|civilDay`
(`JournalViewModel.swift:248`). The VM is created once in
`JournalRouter.start()` (`JournalRouter.swift:30-46`) and the tab view is held
by the shell (`MainTabView.swift:64-70`), so in practice the cache lives for
the app session — matching `Mochi-journal.md` §11's "per session" wording. An
app relaunch on the same day draws (and records) a fresh rotation line via
`observationService.surfaced` → `ledger.nextLine`
(`JournalViewModel.swift:271-275`, `ObservationService.swift:106-125`).
*Moving it into ObservationLedger:* the ledger is UserDefaults-backed,
per-UID, device-local (`ObservationLedger.swift:53-79`) — **not Firestore** —
so the move costs zero synced writes. Add a `journalLines: [String: String]`
field to `ObservationLedger.State` (`ObservationLedger.swift:31-49`), consult
it in the card path, prune non-today keys on write. The live path already
saves ledger state twice per surfaced line (`recordSurfaced` and `nextLine`
each save — `ObservationLedger.swift:154-179, 183-195`); folding the cache
entry into `recordSurfaced`'s save adds **zero** extra writes, a separate save
adds at most 3 UserDefaults writes per day (the 3-line card cap,
`JournalViewModel.swift:243`). One wrinkle: the state is dropped wholesale on
algorithm/schema version mismatch (`ObservationLedger.swift:66-74`) — the
cache would ride along, which is correct behavior. This also fixes the
momentum asymmetry (§11's "may show the NEXT line in rotation") since the
persisted line would survive relaunch.

### 1b. The trial/letter timing gap

Inputs, all verified: trial is 7 days (`MembershipStore.swift:6` comment;
hardcoded in the local store at `MembershipStore.swift:147`; in production the
length comes from the App Store intro-offer product config — RevenueCat only
reports `endsAt` (`RevenueCatMembershipStore.swift:95-97, 133-137`), so the
7-day figure is store configuration, not code — mark that facet UNVERIFIED
from this repo). Trial starts at the onboarding paywall
(`PaywallViewModel.swift:39-43`); adoption is stamped at the naming beat in
the same onboarding session (`PetIdentityStore.swift:122-130`), so
trial-start ≈ adoption-instant for timing purposes.

The letter schedule: `firstEligiblePeriodStart` is the Monday *after* the
adoption week (`LetterPeriod.swift:92-107`); the first eligible period's
cutoff is that week's send day at the effective send hour — default Sunday
19:00, bedtime-clamp only ever earlier (`LetterPeriod.swift:111-152`,
`LetterConstants.swift:14-18`). The letter becomes readable on the first
foreground after the cutoff (`LetterCompositionService.swift:198-234`).

**Earliest first letter:** adopt on a Sunday → adoption week ends that day →
first eligible period is the very next Monday → cutoff the following Sunday
at ~19:00. Days since adoption ≈ **6.8–7.0** (adoption late Sunday evening
compresses it below 7×24h).
**Latest (structural):** adopt on a Monday → the adoption week burns six more
days → cutoff lands on **day 13** at ~19:00 (later still if the user doesn't
foreground; unbounded in wall-clock but the *earliest possible sighting* is
day 13 evening).

**Can any user see their first letter inside the 7-day trial? Yes — but only
one sliver:** a Sunday adopter whose adoption instant falls *after* that
Sunday's effective cutoff hour. For them, trial end (adoption instant + 7×24h)
lands after the next Sunday's cutoff, opening a window of at most ~5 hours
(adoption 23:59 → window 19:00–23:59 on trial day 7), wider where the bedtime
clamp pulls the cutoff earlier. Every other adopter — six days out of seven,
plus Sunday adopters before the cutoff hour — **ends the trial having never
seen a letter**, by 0 to ~6.8 days. The Journal's marquee artifact is
invisible during the entire evaluation window for ~95%+ of users.

Options the code structurally allows (each with what it touches):
1. **Tune `letter_send_weekday` / `letter_send_hour`** — live RC keys
   (`RemoteTuning.swift:240-241`, → `LetterConstants.swift:15-18`). Moving
   send day to e.g. Friday makes the earliest sighting day 4–5 and the latest
   day 11. Touches *everyone's* ritual (the Sunday-evening identity), and per
   the baked-at-compose rule changes future letters only.
2. **Relax the first-period gate** so the adoption week's partial period
   composes (`LetterCompositionService.swift:213-219`). Touches: the gate's
   stated rationale, `trailingAverage` (nil for the partial week —
   classification can't be `great`/ratio-`rough`, `PeriodSummaryBuilder.swift:84-98`),
   the young-state promise copy at `JournalView.swift:107` ("After your first
   full week together…"), `plannedLetterInput`'s same gate
   (`LetterCompositionService.swift:109-115`), and tests. A 2-day-old partial
   letter will be thin — mostly `quiet`/`steady` with no history.
3. **Lengthen the trial** (App Store Connect intro-offer config; zero code).
   A 14-day trial mathematically guarantees the first cutoff (≤ day 13,
   ~19:00) lands inside the trial for every adopter.
4. **A synthetic "first letter"/welcome artifact** — nothing in the code
   supports this; it is a new composer path and a new artifact class. Flagged
   in §4 as a D1/D3 violation candidate rather than silently discarded.
5. `debugForceCompose` exists but is `#if DEBUG`
   (`LetterCompositionService.swift:177-194`) — not a shipping option.

### 1c. listTimeOfDay divergence gate — is there anything left to say

The extension is specced (`mochi-requirements.md:3131-3196`) and unbuilt — no
`listTimeOfDay` case exists in `ObservationKind` (`ObservationTypes.swift:16-22`).
The divergence gate: a list qualifies only when its band differs from the
qualified global band, or no global band is qualified
(`mochi-requirements.md:3158`).

**The repo cannot answer how often a list would qualify AND diverge.**
Verified attempts:
- The DEBUG observation inspector (`DevObservationInspector.swift`) evaluates
  the five *built* kinds over the signed-in user's live data
  (`snapshot.candidates`, `DevObservationInspector.swift:68-90`); it has no
  listTimeOfDay computation and no way to project unbuilt gates.
- There is no fixture, seed, or demo dataset anywhere in the app target
  (searched: `DevSchedulerScreen.swift` has no seeding action; no
  fixture/demo/seed hits outside tests). Test data
  (`ObservationEngineTests.swift` etc.) is synthetic and gate-shaped — it can
  verify the gate logic but says nothing about real-world frequency.

**UNVERIFIED, and unverifiable pre-build.** What would answer it, cheapest
first:
1. *Dogfood instrumentation (hours):* a DEBUG-only inspector row that computes
   the specced gates over the existing inputs — everything needed is already
   fetched: `records` carry `listId` and `completedLocalMinute`
   (`ObservationEngine.swift:185-197` already scopes distributions by list),
   and the global incumbent comes from the same snapshot. Zero production
   surface, answers the question for the dogfooding accounts only.
2. *Ship-dark telemetry (the real answer):* build the engine type but hold the
   card surfacing behind an RC flag; `observation_evaluated
   type=listTimeOfDay qualified=true|false` (the existing denominator event,
   `ObservationService.swift:177-194`) then measures the qualify-AND-diverge
   rate across the fleet before a single line renders.

One a-priori observation worth recording: the global timeOfDay gate needs a
≥40% share of *all* completions (`ObservationConstants.swift:36-39`). Any list
holding a large fraction of the user's completions is therefore strongly
correlated with the global band by construction; divergence requires a
*minority* list with its own concentrated rhythm (≥15 capped completions, ≥40%
band share, 1.5× margin) pointed at a *different* band. That is a genuinely
narrow population — the spec's silence-by-default posture is doing a lot of
work, and the build could plausibly ship and almost never speak. That risk is
exactly why instrumentation should precede the build.

### 1d. Two derivations of "when you work"

The two surfaces **share the band vocabulary but not the derivation**:

| Axis | Journal / noticed card (Observations) | Best Hours (You/Stats) |
|---|---|---|
| Band constants | `TimeOfDayBand`: morning 05–12, afternoon 12–17, evening 17–21, night 21–05 (`ObservationTypes.swift:26-40`) | **Same enum**: captions via `TimeOfDayBand(minute:)` (`BestHours.swift:271-274`); axis origin 05:00 explicitly matched to it (`BestHours.swift:35-38`) |
| Population | **All** completions, recurring included (`ObservationEngine.swift:448-450`) | **Recurring excluded** (D2 rule, `BestHours.swift:49-56`) |
| Shape | Fixed 4-band histogram, top band | Sliding best 3-hour window on the 5a–5a circle (`BestHours.swift:92-98`) |
| Window | Fixed 42 days + qualification gates + 14-day hysteresis (`ObservationConstants.swift:21, 36-43, 66`) | User-selected 7/30/90-day range, default 30 (`StatsBehavior.swift:17-44`, `StatsViewModel.swift:100-110`); peak shown from the first completion, caption gated only on row floors |
| Day cap | 3/day (`ObservationConstants.swift:27`) | Same cap, same stride-sampling, deliberately copied (`BestHours.swift:180-194`) |

**Concrete visible disagreement.** A user with one daily recurring habit
checked off at 8:00 every morning, plus ~12 one-off completions scattered
17:00–20:00 over the month:
- Journal card: all completions count → morning ≈ 42 capped vs evening ≈ 12 →
  share ~72%, margin 3.5× → qualified `morning` → **"Mornings are when things
  happen around here. {name} noticed."** (`Mochi-journal.md` §5b pool).
- Best Hours: the recurring 8:00 rows are excluded → only the evening one-offs
  remain → peak window ≈ 5p–8p → caption **"You get the most done in the
  evening. {name} sees it."** (`BestHours.swift:239-247`).

Two sibling surfaces, both in the pet's voice, using near-identical framing
("{name} noticed" / "{name} sees it"), naming opposite bands. Both are
defensible: Best Hours deliberately measures *discretionary* habit shape (its
D2 comment, `BestHours.swift:10-12`), the observation measures *all* behavior
(its stated rationale, `ObservationEngine.swift:448-449`). But nothing in
either copy register tells the user they measure different things.
*To reconcile:* aligning populations means changing Feature 4's timeOfDay
semantics — an `algorithmVersion` bump that wholesale clears surfacing cadence
(`ObservationConstants.swift:69-72`, `ObservationLedger.swift:66-74`) — or
changing Best Hours' D2 stance, which its own guide locks. *To keep separate*
(my read of the cheaper honest fix, decision in §4): differentiate the copy so
each surface names its scope — Best Hours already has the distinct-verb rule
for exactly this reason (`BestHours.swift:305-308`); the collision above shows
the rule isn't strong enough when the *bands* disagree, not just the verbs.

### 1e. Accessibility sweep of the Journal surface

Verified against `JournalView.swift` top to bottom:

| Element | Treatment | Verdict |
|---|---|---|
| Header title | `.isHeader` (`:61`) | Good |
| Lapsed header pet | hidden (`:73`) | Good |
| Young-state pet | **not hidden, no petName passed** (`:82`) → announces "Mochi, feeling content" via `MochiPetView`'s label (`MochiPetView.swift:265`, default name `:85`) — **wrong name for a renamed pet** | Fix: pass `viewModel.petName` or hide |
| Young-state "Day one" chip | `sparkles` image not hidden (`:85-87`) → VoiceOver reads "Sparkles, Day one" | Minor noise |
| Hero card | explicit label + hint (`:195-196`); label honestly omits the "this week" claim | Good (better than the visual) |
| Letter rows | explicit label with unread state, date, excerpt (`:304-308`) | Good |
| Moment rows | `children: .ignore`, label = rendered text, value = short date (`:338-340`). **The stored `accessibilityTextSnapshot` — written by every producer with the full spoken date incl. year (`MomentFactory.swift:129-131`, `MomentCopy.swift:63`) — is never read by the view.** `Mochi-journal.md` §3b claims it makes rows self-contained: **DRIFTED**. Consequence: a 2025 moment reads as "Jul 18" with no year (the year lives only in the month header) | Fix: use the snapshot as the value |
| Rail dots | hidden (`:255`) | Good |
| Month headers | `.isHeader` (`:206`) | Good |
| Noticed card | header trait (`:360`), sparkle glyphs hidden (`:368`), pet face hidden (`:356`) | Good |
| Week strip cells | `"{narrow letter}: N tasks done"` (`:413-414`) — **"T: 3 tasks done" is ambiguous** (T = Tuesday/Thursday, S = Saturday/Sunday); the visual has the same ambiguity but sighted users get positional context; a formatter for full names is one line (`JournalTimeline.swift:189-191` already builds the narrow one) | Reads worse than the visual |
| 28-day trend chart | **no accessibility treatment at all** (`:421-446`) — relies on Swift Charts' auto-generated element; no summary label ("28 days, N done, quietest/busiest…"), no `accessibilityChartDescriptor` | Weakest element on the surface |
| Footer count + best streak | combined labels (`:460-461`, `:481-482`) | Good |
| Lapse desaturation (`:145`) | purely visual; the subtitle "napping · paused" carries the state for VoiceOver (`:294-296`) | Acceptable |

---

## 2. Dead data table

Schema audit, `Moment` (schemaVersion 1, `Moment.swift:36-62`) — every field
against every read site outside `Moments/` serialization and tests:

| Field | Writer | Reader today | What a reader could do with it |
|---|---|---|---|
| `renderedTextSnapshot` | every producer via `MomentFactory` | Timeline rows (`JournalTimeline.swift:119`), young state (`JournalViewModel.swift:157`) | (alive — baseline) |
| `occurredOn` | every producer | dating/grouping (`JournalTimeline.swift:114-120`) | (alive) |
| `accessibilityTextSnapshot` | every producer (`MomentFactory.swift:129-131`) | **none** — decoded (`MomentRepository.swift:63`) and dropped; `JournalView.swift:338-340` rebuilds a worse label from parts | The intended VoiceOver row text with full spoken date. Zero-cost fix: carry it through `MomentRow` |
| `petNameSnapshot` | adoption (named), streak, vacation producers; nil where unknowable | **none** (letters' same-named field IS read — `LetterDetailViewModel.swift:44-47`) | A detail sheet could say "you called them Momo then" — the renamed-pet postcard beat, already the letters' precedent |
| `subjectNameSnapshot` | listReturn only (`MomentFactory.swift:104-107`) | **none** | Detail sheet: the list's name *as of the event*, rename/delete-proof — the row text already embeds it, but this field is the structured form (e.g. "this list is now called X") |
| `localeIdentifier` | every producer | **none** | Provenance ("written in French"); honestly, mostly future-proofing for a localization pass — weakest of the set |
| `copyDeckVersion` | every producer (`MomentFactory.swift:135`) | **none** | Postcard provenance; also the only way a future detail view could style old-deck prose differently. Diagnostic, not user-visible depth |
| `sourceEventId` | listReturn only (`MomentFactory.swift:107`) | **none** | The provenance link to Feature 4's event key (`listReturn:{listId}|{firedOn}`) — a detail sheet could resolve the *live* list (renamed? still exists?) and offer "open this list" navigation |
| `createdAt` | every producer | **none** user-visible (repo comment notes nothing orders by it, `MomentRepository.swift:99-101`) | "Noticed three days later" late-mint honesty in a detail sheet; also the only record of a deferred anniversary being deferred |
| `type` | every producer | icon + origin-dot only (`JournalTimeline.swift:121-123, 167-175`) | Detail-sheet framing per type |

The headline: **five of ten stored fields have zero readers**, and the richest
consumer surface for all of them is the same one feature — a moment detail
sheet (§3b). This is the cheapest depth in the codebase: the data is already
in Firestore, already validated by rules (`firestore.rules:70-88`), already
flowing through the cache (`CachingMomentRepository.swift:40-50`).

---

## 3. Feature feasibility table

| Idea | Files touched | Schema / rules / RC | Doctrine touched | Size |
|---|---|---|---|---|
| (a) "First noticed" moment | `ObservationTypes/Engine` (expose transition), `MomentWriter/Factory/Copy`, a call site (`JournalViewModel.load` or `MemoriesService.assignPersonalLayer`), `firestore.rules`, `Mochi-journal.md` | New moment type → **rules enum + id-prefix change and deploy** (`firestore.rules:78-87` is a closed set); no RC required | **D3 head-on** (freezing a derived, retirable conclusion into the create-only timeline); D5 subtlety below | **M–L**, and the honest answer is "expensive" — see below |
| (b) Tappable moment rows + detail sheet | `JournalView` (row → Button), `JournalBehavior` (`MomentRow` carries full moment / new sheet state), `JournalViewModel`, new `MomentDetailView`, small pure letter-resolution helper | None. Letter resolution is derivable from the letters array alone (below) | None violated; D3 *served* (renders frozen fields) | **S–M** |
| (c) Month-bounded pagination / year-month jump | `MomentRepository` + `CachingMomentRepository`, `LetterRepository` + caching twin, `JournalViewModel` (accumulate pages), `JournalView` (jump affordance) | None (query-shape change only; rules untouched) | D5 fine (stored-date grouping already zone-pinned) | **M** |
| (d) "Weekly shape" letter beat | `PeriodSummary`, `PeriodSummaryBuilder`, `LetterComposer` (beat priority + insight-family rule), `LetterCopy` (new pool, deck version bump), `LetterConstants`/`RemoteTuning` if thresholds tunable | No schema/rules; **RC keys if gated remotely** (console pin moves again) | D4 (phrasing must affirm divergence, never frame as deviation); D1 untouched (this is Feature 3, not a Journal engine); D5 fine (compose-time fact like momentum) | **M** |
| (e) Shareable moment cards | Extract `ActivityShareSheet` (currently `private` in `LetterDetailView.swift:163-176`), new `MomentShareCard` view (clone of `LetterShareCard`, `LetterDetailView.swift:180-219`), share entry point (needs (b) or a context menu), telemetry event | None | None; moment copy is already count-bearing by design where counts are records | **S** on top of (b) |

**Feature (a), the load-bearing detail you asked for:** the engine exposes a
current-state verdict *plus* `stableSince` (`ObservationTypes.swift:85-91`),
and within one `evaluate()` the replay even shows the day the incumbent was
established (transition = `stableSince + stickyDays − 1`,
`ObservationEngine.swift:728-732`). So a transition *day* is derivable — **but
it is not stable over time**. The replay folds from an empty seed over a
sliding 90-day window (`ObservationEngine.swift:691-693`); once an incumbent's
originating streak start slides past the horizon, `stableSince` becomes the
replay-window start and **drifts forward one day per day**. Consequences:
- A natural id keyed on the derived qualification day is only stable for
  ~76 days (90 − 14) after qualification; after that, every day derives a
  different id → duplicate moments, violating the id-identifies-an-event
  contract (`Moment.swift:40-42`).
- Dedup therefore cannot be purely derived; it needs a read-and-check against
  the existing moments collection (which `JournalViewModel.load` happens to
  hold — `JournalViewModel.swift:121`) or stored first-qualified state, which
  is exactly the "no stored stability state" line the engine was built to
  avoid (`ObservationEngine.swift:12-14`).
- And minting only from the Journal load means users who don't open the
  Journal never get the moment — the event becomes surface-dependent, which
  no other moment is.
So: not cheap. The idea's real cost is a new dedup convention plus a D3
exception, not the UI.

**Feature (b) letter resolution, verified mechanics:** a letter's attribution
window is previous-cutoff → own-cutoff (`LetterPeriod.swift:80-87`). For
*display* purposes the honest derivation uses only stored postcard truth:
sort letters by `periodEndExclusive`; moment M (date-only `occurredOn`,
anchored in the letter's stored zone) belongs to the earliest letter L with
`M < L.periodEndExclusive` and `M ≥ previous-letter.periodEndExclusive`.
Re-deriving historical cutoffs via `LetterSchedule` with *today's* bedtime
would be wrong (the clamp is baked per-letter); the stored-ends-only approach
never is. Two honest edge cases to spec before build: a moment in a dormant/
vacation gap has **no** owning letter (render nothing — absence over guess),
and a date-only Sunday moment straddling the cutoff hour is ambiguous — the
resolution should say "the week of…" not claim precision.

**Feature (c), verified premises:** the composer takes plain arrays —
CONFIRMED (`JournalTimeline.monthGroups(letters:moments:...)`,
`JournalTimeline.swift:82-88`, pure merge). Both repositories currently read
whole collections (`MomentRepository.swift:86-92` with the comment
"month-bounded paging can slot in behind this API" at `:18-20`;
`CachingLetterRepository.swift:8-9`), and the repo already has a proven
cursor-pagination pattern to mirror: `completedTasksPage(limit:after:)`
(`TaskRepository.swift:139`, `CachingTaskRepository.swift:236-256`) with an
accumulating view model (`TasksViewModel.swift:36-108, 445-455`, built for the
Done timeline in commit f7cbd64). The real design question is whether the
Journal *needs* it yet: moments accrue "at relationship speed" and letters at
52/year — the whole-collection read is dozens of docs for a year-old account,
and the write-through cache makes revisits free. Pagination is plumbing for
year three; the **jump affordance** (an anchor-scroll over already-loaded
month groups) is separable and much cheaper than true paging.

**Feature (d), verified premise:** the distribution is reachable without any
new query — CONFIRMED. `buildSummary` already holds `periodStats` (the
window's completions) whose records carry `completedLocalMinute`
(`LetterCompositionService.swift:275, 285-298`; band via
`TimeOfDayBand(minute:)` exactly as the engine does it,
`ObservationEngine.swift:319`), and it already runs the full engine evaluation
for the qualified trait (`LetterCompositionService.swift:406-426`). A
"week's shape vs. qualified band" divergence fact is a pure
`PeriodSummaryBuilder` function over inputs already in hand. Composer-side
cost is real but bounded: a new optional beat must slot into the priority
order and respect the one-insight-family rule
(milestone > comeback > bestDay > observation > listReturn, at most one of the
insight family — this beat is a second "Mochi analyzed you" and must join that
XOR family or the three-beat letter can carry two analyses). D4 risk is the
core copy problem: "this week was different" must never read as "you fell off
your rhythm." Falling *volume* is already silence; a *shifted* week can be
framed as noticing, not correcting — but that's a copy-review gate, not a code
gate.

---

## 4. Doctrine tensions (decisions for a human, deliberately unresolved)

1. **First-noticed moments vs. D3.** The requirements doc already ruled once,
   for listTimeOfDay: "the conclusion is derived and can strengthen, shift
   bands, or evaporate — freezing it into the timeline would violate
   record-vs-derive" (`mochi-requirements.md:3142-3147`). Feature (a) is that
   exact move for the existing traits. The counter-argument worth weighing:
   *the moment of first qualification* is arguably an event that happened (Mochi
   did start saying it), not a conclusion that persists — the same reasoning
   that lets listReturn (a derived event) mint a moment today. If you break D3
   here, the listTimeOfDay "not a moment" ruling should be re-argued too, or
   the doctrine becomes "D3 except where we liked the feature."
2. **Best streak vs. D2.** Is a frozen personal best a record or a standing
   target? The tile survives the record-vs-grade test only under the reading
   "records of the past are not grades of the present." If that reading holds,
   consider losing the flame (achievement register) while keeping the number;
   if it doesn't, the tile goes. Middle grounds exist (e.g. reframe as
   "Longest run · 12 days" — same fact, calmer register) but any of them is a
   judgment call about what "grade" means, which is not mine to make.
3. **Anniversary repair vs. the lapse silence.** The bounded repair (§1a) is
   cheap and honest for the unopened-app case. The genuinely contested slice
   is lapse-covered marks: adoption synthesis says "recording an existing
   fact is allowed even lapsed" (`MomentWriter.swift:121-124`); Feature 2 says
   backdating anniversaries at resubscribe is guilt manufacturing
   (`MemoriesService.swift:12-14`). Both precedents are in the codebase.
   A repair could exclude lapse-covered marks and still fix the common case —
   but that scoping is a values choice.
4. **Trial users never meeting the letter.** Every remedy breaks something
   doctrinal: composing the partial adoption week breaks the first-full-week
   promise (and its in-app copy); a synthetic welcome letter is a new engine
   (D1) producing a derived artifact into the permanent archive (D3-adjacent);
   moving send day reshapes a ritual for everyone to serve week one; only the
   trial-length change (option 3) is doctrine-clean, and it's a business
   decision outside this codebase.
5. **Two truths about "when you work."** Keeping both derivations is honest
   (they measure different populations) but currently *reads* dishonest — same
   voice, same band words, opposite conclusions possible (§1d). Reconciling
   the data means an algorithmVersion bump or a Best Hours philosophy change;
   reconciling only the copy means admitting scope in the pet's voice
   ("your one-offs…" vs "everything…"), which fights the no-measurement copy
   rule. One of the three has to give.
6. **"More involved" vs. the container.** Features (b), (c), (e) add depth by
   *rendering more of what exists* — squarely inside D1. Features (a) and (d)
   add depth by *producing more* — each is a new producer, and each next
   producer makes "container, not engine" less true as a description of the
   tab's gravity. Worth deciding explicitly how much production the Journal's
   orbit is allowed to accrete before the constraint is fiction.

---

## 5. Cheapest three, by user-visible depth ÷ cost

1. **Tappable moment rows + detail sheet (b), with the dead fields as the
   payload.** Cost S–M, zero schema/rules/RC, zero doctrine friction — and it
   is the *only* consumer that turns five already-stored, never-read fields
   into visible depth (§2): the frozen pet name of the day, the letter whose
   week contained the moment, the frozen list name, "noticed later" honesty
   from `createdAt`. The Journal's stated identity is postcards; this is
   turning the postcards over. It also carries (e) almost for free afterward.
2. **Truth-and-polish batch: hero chip honesty + the a11y fixes.** Nearly
   free (a derived boolean/date in `HeroLetter`; pass the a11y snapshot
   through `MomentRow`; full weekday names in the strip labels; petName on
   the young-state pet; a summary label on the trend chart) and it repairs
   the two places the surface currently *says something untrue* — the chip's
   false "this week" and the wrong pet name — plus the spec-drifted VoiceOver
   row. Depth isn't only new features; a surface that never lies is what the
   doctrine is for.
3. **Bounded anniversary repair (N-day, vacation-aware, lapse-excluded).**
   Cost S (one pure scan + idempotent writes, both patterns already shipped in
   this codebase), no schema/rules/RC change, and it fixes a real hole in the
   *record* itself: today a month mark simply vanishes from the permanent
   timeline because the user didn't open the app on the right day — the
   timeline under-records the relationship it exists to record. Scope the
   lapse question out (§4.3) and the rest is uncontested.

(Feature (d) is the best of the *producer* ideas but is M-cost with a real
copy-review gate; (a) looks cheap and is not (§3); (c)'s paging is premature
while the jump affordance alone is a candidate for a later batch.)

---

## 6. Open questions the code could not answer

1. **Actual production trial length.** The 7-day figure is a comment and the
   local stub (`MembershipStore.swift:6, 147`); the shipping length lives in
   App Store Connect / RevenueCat product config, which this repo does not
   contain. *Answer:* check the intro-offer configuration (or
   `mochi-pending-integrations` follow-ups) before reasoning further about
   §1b remedies.
2. **listTimeOfDay qualify-AND-diverge rate.** Unanswerable from the repo (no
   fixtures, inspector computes built kinds only). *Answer:* the DEBUG
   inspector row for dogfood accounts, then ship-dark
   `observation_evaluated` telemetry behind an RC flag (§1c) — in that order,
   before committing to the build.
3. **How often the hero chip currently lies.** Depends on unread-letter aging
   in the field; telemetry has `timeToOpenBucket` on opens
   (`LetterCompositionService.swift:147-154`) but nothing measures
   hero-impression-while-stale. *Answer:* the existing
   `journal_section_impression` plus letter-open buckets can bound it
   coarsely; a precise answer needs an impression parameter (age bucket of the
   promoted letter) — names-only telemetry doctrine permits a bucket.
4. **Whether anyone shares letters at all.** (e)'s value hangs on the letter
   share path seeing use; `letter_shared variant=` exists
   (`LetterDetailView.swift:57-59`, `LetterTelemetry`). *Answer:* read the
   telemetry before building moment cards.
5. **Real archive sizes.** Pagination (c) is justified by document counts this
   repo can't see. *Answer:* Firestore console distribution of
   `letters`/`moments` collection sizes per user, or defer until the
   whole-collection read demonstrably hurts (the call meter,
   `FirestoreReadLog`, would show it first).
6. **Whether the Sunday-adopter trial window ever fires in practice.** The
   ~5-hour sliver (§1b) assumes same-evening onboarding completion and a
   post-cutoff foreground; no analytics in this repo can confirm a single user
   has ever hit it. *Answer:* funnel data (adoption weekday × hour), which
   lives in the telemetry backend, not here.
