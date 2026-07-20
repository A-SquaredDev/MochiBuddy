# Mochi — Design Doc

*Working title. A companion-driven reminders & todo app.*
*Status: living draft — v0.6 · implementation current through v0.5 (see Implementation status)*

---

## Changelog

**v0.6 — July 19 2026** *(current)*
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

> 🛠 **As of July 19 2026.** Everything the changelog resolved through v0.5 is now built,
> in the app target, and covered by the automated suite: **350 tests, 0 failures**
> (`MochiBuddyTests`, Swift Testing, app-hosted). v0.6 (Widgets) is designed but not yet
> started; it needs a new WidgetKit target + App Group capability. Constants marked
> "Remote Config" throughout this doc currently live in code as `Constants` enums
> (`MoodEngine`, `NotificationPlanner`, `VacationConstants`); actual Remote Config wiring
> is deliberately deferred.

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
  bedtime, prefs, entitlement change, notification actions. **Still unwired:**
  `EKEventStoreChanged` and timezone change.
- Streak-milestone **notifications** wait on the widget (v0.6, complete-from-widget is
  their trigger); the detection hook (`ToggleOutcome.milestoneStreak`) is in place with no
  in-app celebration surface yet.
- Snooze targets: tonight = 19:00 (or an hour out if already evening), tomorrow = 09:00.
- Trial expiry mid-session is caught at flow entry / You-tab refresh, not by a live
  listener; consistent with "trial expiry is not an auth event."

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
- **7-day free trial, then subscription. No freemium tier.** The emotional hook
  needs a few days to land (you have to fall behind once and feel Mochi react), so
  the trial gives the full experience before the ask.

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
   **"Mochi, shh — 24h"** action; plus a **"how chatty is Mochi" dial** (Quiet / Normal /
   Chatty, default Normal) and vacation mode. The easiest way to quiet Mochi must never be
   iOS's system-level off switch.

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
- **Budget priority over the 64-slot cap:** promises by nearest due → mood pings → rundowns.
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
- `timezone` (IANA, current), `bedtimeStart`, `bedtimeEnd`
- `themeId`, `interests[]`
- `coins`, `dailyCoinsEarned`, `dailyCoinsDate` (diminishing-returns cap)
- `streakCount`, `lastActiveDate`
- `isSubscribed`, `trialEndsAt` (mirrored; RevenueCat is source of truth)
- `notificationPrefs`

`users/{uid}/lists/{listId}` — `name`, `color`, `icon`, `order`

`users/{uid}/tasks/{taskId}`
- `title`, `notes`
- `dueAt` (UTC Timestamp, nullable), `hasTime` (bool), `dueTimeZone` (IANA)
- `priority` (low | med | high)
- `listId` (nullable → Inbox)
- `repeatRule` (nullable: `{freq, interval}`)
- `completed` (bool), `completedAt` (nullable)
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

**Navigation: three tabs — Home · Tasks · You.**
- **Home** — Mochi (mood + tap to pet), coin pill, today's tasks, quick-add.
- **Tasks** — Today / Upcoming / Lists / Completed.
- **You** — profile: streaks & stats, flavors, bedtime, notification prefs, vacation
  mode, manage lists, **account & legal**.
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
2. Show exactly what's destroyed (tasks, lists, coins, streak, Mochi) — irreversible.
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
  re-signing-up does **not** grant a fresh 7-day trial.

## Entitlement & subscription states

> 🆕 **v0.3 — RESOLVED.**

**Trial expiry is not an auth event.** The Firebase Auth session persists indefinitely;
only the RevenueCat *entitlement* lapses. Never log a user out to gate them — they'd just
log back in for free. **RevenueCat is the single source of truth**; the Firestore
`isSubscribed` field is an offline cache only, never computed locally.

| State | Source | Access |
|---|---|---|
| `trialing` | RC | Everything. 7 days. |
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
| Stats | Viewable, frozen. |
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
   mood animations. The emotional hook.
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

## Still to flesh out

- **Screens not yet designed:** paywall, sign-in, onboarding, notification primer,
  Apple Reminders settings, account & legal section of "You."
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
