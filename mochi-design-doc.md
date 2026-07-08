# Mochi — Design Doc

*Working title. A companion-driven reminders & todo app.*
*Status: living draft — v0.2*

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
- **Vacation mode:** freeze baseline / suppress stress accrual + notifications.

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

Tied to mood, but capped and user-controllable. Happy → rare/none. Anxious →
~1/hr. Sad → more, with a **hard daily ceiling**. Tone is endearing, not nagging
("Mochi misses you" > "5 TASKS OVERDUE"). Sleep enforces quiet hours automatically.

**Still to hammer down:**
- **Scheduling architecture (the crux):** iOS can't fire mood pings reactively —
  local notifications must be pre-scheduled and iOS caps pending ones at **64**. So
  *predict* threshold crossings from known due dates, pre-schedule, and re-lay on app
  foreground / task change (background refresh is unreliable). Everything else sits on this.
- **Cadence + cap:** exact pings/hour per state, escalation speed, the hard daily
  ceiling, minimum spacing, and **coalescing** (5 overdue = 1 summary, not 5 pings).
- **Copy:** a *library* of lines per state (avoid repetition fatigue); name the task
  vs stay vague (lock-screen privacy → maybe a setting); stay endearing even at "very sad."
- **Inventory — incl. positive:** task-due · just-overdue · mood escalation · morning
  rundown · **celebrations/streaks**. Decide the winback/lapsed-user line (manipulation risk).
- **Actions + richness:** mark done / snooze / pet from the notification; Mochi mood
  image attachment; interruption level (gentle pings passive; user-set due times may be
  time-sensitive).
- **Controls + tuning:** per-type toggles + a "how chatty is Mochi" dial; quiet hours;
  denied-permission fallback (badge-only, or start with *provisional* auth); cadence
  constants in Remote Config + analytics on opens-vs-uninstalls.

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
- **Widgets** show a *still image* of Mochi's current mood (one export per state/theme)
  — they can't run the live animation. Home-screen widget refreshes every ~15–60 min
  automatically, and instantly when the app is foregrounded (foreground + intent-driven
  reloads don't count against the ~40–70/day budget). Tap-to-pet = an interactive-widget
  button (iOS 17+) running an App Intent that bumps the buffer and reloads; completing a
  task from the widget is possible too. Lock-screen = a small tinted mood glyph + next
  task. All read state from the App Group.
- **Subscriptions** — StoreKit via **RevenueCat** (plays well with Firebase; handles
  trials, restore, entitlement checks).
- **EventKit** — optional Apple Reminders import; full-access reminders permission +
  `NSRemindersFullAccessUsageDescription`. iOS-only.

## Feature backlog / ideas

- **Vacation mode** *(confirmed — user loves it)* — pause the nudging entirely for
  travel / rest / sick days. Protects trust and wellbeing.
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

## Still to flesh out

- **Screens not yet designed:** paywall, sign-in, onboarding, notification primer,
  Apple Reminders settings, account & legal section of "You."
- **Notification mechanics** — scheduling architecture, copy library, daily-cap
  enforcement, quiet hours (see Notifications section).
- **Procrastination signal (v2)** — repeated snoozing never triggers "overdue," so
  Mochi never notices. Detect chronic rescheduling.
- **Accessibility** — mood conveyed beyond color/sound (VoiceOver labels), reduced-motion.
- **Platform scope** — iOS first, Android later? (Apple/Google auth + lock-screen
  widgets + Watch + Apple Reminders all lean iOS.)
- **Empty states** — "nothing due today" (calm) vs "all caught up" (celebration). Both
  mocked; keep them distinct.

---

## Open questions

1. Exact bedtime default (e.g. 10pm–7am?) and morning-rundown send time.
2. Diminishing-returns curve for coins — how many full-value completions per day
   before it tapers?
3. The task app itself: recurring tasks / routines, subtasks, tags, priorities —
   which make the first version vs. later?
4. Onboarding flow — how do we introduce Mochi and set expectations in the first
   30 seconds?
