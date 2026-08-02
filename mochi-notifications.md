# MochiBuddy notification system

An investigation of every notification genre the app can send, the scheduling
model behind them, the mood escalation math, remote tuning knobs, and bugs
found during the review. All line references are against the current working
tree.

## Architecture in one paragraph

Everything is local notifications, no push. The system is a "re-lay" loop:
`NotificationOrchestrator.relayNow` (MochiBuddy/Notifications/NotificationOrchestrator.swift:194)
snapshots the world (`makeContext`, line 148), folds the current mood band into
the persisted taper state, asks the pure `NotificationPlanner.plan`
(MochiBuddy/Notifications/NotificationPlanner.swift:71) for the full desired
pending set over a 7 day horizon, diffs it against what iOS actually has
pending (`NotificationPlanDiffer.diff`, MochiBuddy/Notifications/NotificationPlanDiff.swift:33),
removes stale app-owned ids, and (re)schedules everything desired. Adds with an
existing identifier replace atomically. Re-lays are triggered by every app
foreground, task change, comfort change, vacation change, bedtime change,
prefs change, entitlement change, notification action, timezone change, pet
rename, letter change, and external Apple Reminders change
(`RelayTrigger`, NotificationOrchestrator.swift:18; call sites wired in
MochiBuddy/App/AppContainer.swift:242-308 and MochiBuddy/App/RootView.swift:54,125).
`requestRelay` debounces mutation storms with a 300 ms delay
(NotificationOrchestrator.swift:124-131). Mood predictions are pre-evaluations
of the same deterministic `MoodForecast` curve the app shows on open
(MochiBuddy/Mood/MoodForecast.swift), so a scheduled ping can never disagree
with mood(now) by construction.

## Summary table

| Genre | ID scheme | Trigger | Time | Frequency cap | Quiet hours | Suppressed by | Pref gate |
|---|---|---|---|---|---|---|---|
| Promise (due reminder) | `due-{taskId}` | Timed task with a future due instant | Exact due time; daily/weekly/monthly repeat via one calendar trigger | One per task | Never silenced | Vacation only | `taskReminders` |
| Mood ping | `mood-{band}-{epoch}` | Forecast predicts uneasy, anxious, or verySad band | Band-entry crossing, then per-band spacing | 1 to 4 per day by band, floor taper 4/3/2/1, hard ceiling 4/day | Dropped (never shifted) during bedtime window | Shh valve, vacation plus grace, lapsed, slot budget | `moodDips` |
| Morning rundown | `rundown-YYYY-MM-DD` | Every morning in horizon | Wake time (end of bedtime window) | One per day | Fires at wake by definition | Vacation, lapsed | `morningRundown` |
| Backstop | `backstop` | Always laid (dormant-user safety net) | 7 days after last relay, repeating | One pending slot, weekly | Not checked | Vacation plus grace, lapsed | any pref on |
| Weekly letter invitation | `letter-{periodStart}` | Current letter period is non-dormant | Period cutoff (Sunday 19:00 by tuning) | One per period | Not checked | Vacation, lapsed, adoption-age gate, slot budget (dropped first) | `weeklyLetter` |

Celebrations are deliberately NOT a notification genre: `celebrationPool`
exists in NotificationCopy.swift:108-114 and a `celebration()` renderer at
line 210, but no scheduler path ever emits one. Milestones celebrate in-app
via `CelebrationCenter` (AppContainer.swift:256-267, with the comment
explaining a push would always arrive while the user is already looking at
Mochi). The widget never sends notifications; it mirrors relay context
(`onRelaid`, AppContainer.swift:289-291) and its completions are drained into
the same task pipeline on foreground.

## Genre 1: Promises (due reminders)

- Planner: `planPromises`, NotificationPlanner.swift:99-126.
- Trigger: one exact reminder per incomplete task that has a time
  (`task.hasTime`) and a future `dueAt`. Date-only tasks get no promise; the
  rundown carries them.
- Overdue recurring occurrences promise their NEXT occurrence instead of being
  dropped (NotificationPlanner.swift:113-116), so a user who never reopens the
  app cannot silently lose tomorrow's reminder.
- Repeat economics: daily, weekly, and monthly rules ride a single repeating
  `UNCalendarNotificationTrigger` built by `PromiseTriggerBuilder`
  (MochiBuddy/Notifications/PromiseTriggerBuilder.swift:18-40). Weekdays and
  custom day sets cannot be expressed in one component pattern, so they
  schedule the single next fire and lean on the re-lay
  (NotificationRequestBuilder comment, NotificationScheduling.swift:83-87).
- Delivery: time-sensitive interruption level, `mochi.reminder` category with
  Complete plus a three-option snooze menu (1 hour, tonight 19:00, tomorrow
  09:00; SnoozeOption.swift:13-46). Actions run without opening the app and
  end in a re-lay (NotificationActionHandler.swift:48-101).
- Copy (revised in the 2026-08-02 string review): generic knock title
  "You have something due!" with the task title as the body; the
  `hideTaskNames` privacy pref swaps the body for "One new task is due.
  Check the app to view!" (NotificationCopy.swift:150-159).
  Promise copy never embeds the pet name, the locked rule that lets renames
  leave promises untouched (verified by test).
- Suppression: vacation is the ONE suppression allowed to silence a promise
  (NotificationPlanner.swift:117). Shh, bedtime, and lapsed never touch it.
  Lapsed users keep promises indefinitely and lose everything else
  (NotificationPlanner.swift:77-82).
- Budget priority: first claim on the 64 slots, sorted by nearest due
  (NotificationPlanner.swift:325-341).
- Foreground: promises still banner while the app is open; everything else is
  silenced on-screen (UNNotificationScheduler.swift:164-173).

## Genre 2: Mood pings

- Planner: `planMoodPings`, NotificationPlanner.swift:130-196.
- Trigger: the forecast curve (`MoodForecast.bandCrossings`) is segmented into
  band intervals over the horizon; only uneasy, anxious, and verySad have a
  cadence. Content and better are silence by design: "the happy side is
  carried by real celebrations, never by predictions"
  (NotificationPlanner.swift:55-62).
- Timing: a segment that opens at a band crossing pings at the crossing (no
  entry grace); the capture-time segment starts one spacing out because its
  entry moment already happened in a previous lay
  (NotificationPlanner.swift:153-158). Subsequent candidates step by the
  band's spacing, and cross-segment spacing is enforced through `lastPingAt`
  (line 159-161).
- Quiet hours: candidates inside the bedtime window are DROPPED, never
  shifted, when `bedtimeSilence` is on, so a silent night never dumps its
  pings at dawn (NotificationPlanner.swift:174, 189-192). Default bedtime is
  22:00 to 07:00 wall clock (UserProfile.swift:16).
- Caps (all per calendar day): per-band cadence count, floor taper budget for
  verySad, and a hard global ceiling of 4 mood pings per day
  (NotificationPlanner.swift:163-176).
- Copy: pet-voiced, blame-free, never a task name or count; four pools
  (uneasy, anxious, floor acute, floor chronic) with a persisted round-robin
  deck that never repeats a line until the pool cycles
  (NotificationCopy.swift:37-96, 118-136). Passive interruption level,
  shared `mochi.mood` thread so they stack politely
  (NotificationScheduling.swift:97-107).
- Actions: Pet (adds a comfort buffer boost) and "Mochi, shh"
  (NotificationActionHandler.swift:59-66).
- Shh valve: 24 hours of mood-ping silence; candidates before `shhUntil` are
  dropped; promises and the taper are untouched
  (NotificationOrchestrator.swift:278-292, NotificationPlanner.swift:175).
- Vacation: suppressed while active AND through the post-vacation grace decay
  window (24 h by default) so the wake is gentle
  (NotificationPlanner.swift:355-364).
- The band is baked into the id at scheduling time and the DEBUG scheduler
  inspector verifies baked band == mood(fireAt) recomputed, per ping
  (DevSchedulerScreen.swift:276-283).

### The mood escalation math (the specific question)

Frequency does NOT increase the longer Mochi stays sad. It is the opposite,
and it is deliberate. Two independent axes:

1. Depth escalates. The deeper the predicted band, the more pings per day:
   uneasy 1/day at 4 h spacing, anxious 3/day at 3 h, verySad 4/day at 2 h
   (`cadenceRules`, NotificationPlanner.swift:58-62; bands defined in
   MochiShared/MoodBand.swift:22-31: verySad is 0-15, anxious 15-35, uneasy
   35-50).

2. Duration TAPERS. For the verySad floor only, a per-day budget overrides the
   cadence count based on how many consecutive calendar days the mood has been
   at the floor: `floorTaperBudgets = [4, 3, 2, 1]`, so day 1 = 4 pings,
   day 2 = 3, day 3 = 2, day 4 and beyond = 1 ping/day indefinitely
   (NotificationPlanner.swift:50-52; applied at lines 165-169 as
   `floorTaperBudgets[min(max(ordinal, 1), count) - 1]`, additionally clamped
   by `min(dayBudget, dailyCount)` at line 172). The design rationale is in
   TaperTracker.swift:6-8: "day 1 at the floor is a bad day, day 7 is
   burnout".

Day counting: `TaperTracker.update` (TaperTracker.swift:47-76) folds one band
observation into persisted state on every re-lay. A verySad observation sets
`firstFloorDay` (once) and clears any recovery clock. `consecutiveFloorDays`
is the whole-day distance from `firstFloorDay` to today
(TaperTracker.swift:26-31), and the planner's `floorDayOrdinals`
(NotificationPlanner.swift:228-249) numbers each forecast floor day as
`priorDays + index + 1`, so the taper threads correctly across the lay
boundary: three completed floor days before today makes today ordinal 4,
budget 1.

Copy escalates in tone while volume tapers: the floor pool shifts from acute
(gentle, hopeful) to chronic (pure presence, zero ask) on day 3 of the
stretch, keyed off the same counter (`floorDays >= 2 ? .chronic : .acute`,
NotificationOrchestrator.swift:244).

Reset rules: the stretch resets ONLY on a genuine recovery, defined as the
band reaching content or better and HOLDING it for 24 h (`recoveryHold`,
TaperTracker.swift:38; clear at lines 62-69). An intermediate uneasy or
anxious observation interrupts the recovery clock but keeps the stretch
(lines 70-74), so a momentary blip (one task done, mood pops, slides back
overnight) never resets the taper and can never hand the user MORE pings than
doing nothing. Unobserved gaps between floor sightings carry the stretch,
because mood only rises on action and every action re-lays
(TaperTracker.swift:52-59). All of this is pinned by tests
(NotificationDeliveryTests.swift:17-65).

## Genre 3: Morning rundown

- Planner: `planRundowns`, NotificationPlanner.swift:255-279. One briefing per
  morning inside the (entitlement-capped) horizon, firing at wake, which is
  defined as the END of the bedtime window (`bedtime.endMinutes` added to
  start of day, line 266). Default wake 07:00.
- Content (NotificationRequestBuilder, NotificationScheduling.swift):
  since the 2026-08-02 string review the body never lists a task title, it
  carries the due COUNT ("N tasks are due today."); RundownRanker still runs
  at the rundown's own fire time with recurrence rolled forward, but only
  its totalDue feeds the copy (RundownRanker.swift:14-44).
- Title rotates through the greeting pool ("Good morning" / "Good morning
  from {name}"); a notably productive yesterday (5 or more completions, a
  COUNT never an effort-weighted sum) overrides it as "Good morning. You
  crushed yesterday" (NotificationCopy.swift:169-204). Body is always one
  warm line (or the Personal-Layer opener) plus one compact summary, two
  lines flat.
- Personal Layer: one line per rundown morning (streak milestone, anniversary,
  crushed yesterday, memory callback, or observation, in that canonical
  priority) is assigned for the whole horizon in one deterministic pass by
  MemoriesService and leads the body as an opener
  (NotificationOrchestrator.swift:229-238, AppContainer.swift:183-191,
  MemoriesService.swift:81-149).
- `hideTaskNames` no longer alters the rundown: with the count-only summary
  there is no task title left to hide. The pref still gates reminder bodies.
- Active interruption level, no category (no actions). Suppressed on vacation
  and while lapsed; outside the mood-ping cap; third claim on slot budget.

## Genre 4: Backstop

- Planner: `planBackstop`, NotificationPlanner.swift:309-316. A single
  repeating time-interval trigger 7 days out from the last relay, so a
  dormant user past the horizon still hears from Mochi. Every relay
  reschedules it, which resets the countdown; it only ever fires after 7 full
  days of zero app activity.
- Dressed as a chronic-floor line (pure presence, no ask, safe at any
  staleness), passive, in the mood category
  (NotificationScheduling.swift:154-165).
- Its own genre since the 2026-08-01 fix pass: planned whenever ANY
  notification pref is on, silenced only by a full opt-out (task reminders,
  rundown, mood dips, and weekly letter all off), vacation plus grace, or
  lapse. Holds one reserved slot outside the 63 remaining for everything else
  (NotificationPlanner.swift).
- Its repeating interval is clamped to at least 60 seconds because iOS raises
  an uncatchable ObjC exception below that
  (UNNotificationScheduler.swift:25-45, test at
  NotificationDeliveryTests.swift:567-574).

## Genre 5: Weekly letter invitation

- Planner: `planLetter`, NotificationPlanner.swift:289-303. One invitation at
  the current letter period's cutoff, and only when
  `LetterCompositionService.plannedLetterInput`
  (LetterCompositionService.swift:95-135) supplies an input, which requires:
  not lapsed, not on vacation, at least one full post-adoption period elapsed,
  and the period already NON-DORMANT (a user-visible foreground stamped the
  activity marker, or a completion landed inside the attribution window). The
  scheduling invariant lives at the input boundary: a Sunday invitation is
  never queued for someone who may vanish all week.
- It is the invitation, never the delivery: the letter itself always arrives
  in-app on the next eligible foreground. Send moment tunes via
  `letter_send_weekday` (default 1) and `letter_send_hour` (default 19).
- Tapping routes straight to the letter in the Journal via the id
  (`letter-{periodStart}` equals the letter document id;
  UNNotificationScheduler.swift:147-162, AppContainer.swift:213-215).
- Budget: dropped FIRST under slot pressure because it alone has a full
  in-app backstop (NotificationPlanner.swift:320-341). Never counts against
  the mood-ping cap. Gated by the `weeklyLetter` pref.

## Suppression and budget composition

Order of operations inside one plan (NotificationPlanner.swift:71-92):

1. Lapsed blanks everything except promises (the quiet checklist IS the
   winback; no mood, no rundown, no backstop, no guilt, no letters).
2. Vacation silences everything, including promises; mood pings additionally
   stay quiet through the grace decay window after it ends.
3. Shh silences mood pings only, for 24 h, never touching a promise and never
   resetting the taper.
4. Bedtime silence drops mood-ping candidates inside the window (pref
   `bedtimeSilence`, on by default); promises and the letter ignore it and
   the rundown fires at the window's end by construction.
5. Budget over iOS's 64-slot ceiling: promises by nearest due, one reserved
   backstop slot, mood pings, rundowns, then the letter. A reminder is never
   the thing dropped.
6. Horizon: 7 days, hard-capped at a known entitlement cliff (a real
   cancellation, `willRenew == false`) so nothing but promises is ever laid
   into a lapsed state; an auto-renewing boundary never caps
   (NotificationOrchestrator.swift:296-307, MoodForecast.swift:128-133).

## Permission gating

- One shot at the system dialog, fired only from the onboarding primer after
  the user opts in (NotificationPrimerViewModel.swift:30-52). The choice is
  persisted to the profile as `notificationsEnabled`.
- Users who skipped the primer get provisional (quiet) delivery requested on
  every home entry when status is still notDetermined: degrade, don't disable
  (NotificationPermissionService.swift:32-36, RootView.swift:35).
- The prefs screen surfaces a `systemDenied` banner state but the per-type
  toggles remain the app-level gate (NotificationPrefsViewModel.swift:48-49).
- Note: the orchestrator itself never consults authorization status; it lays
  the pending queue regardless, and `center.add` errors are swallowed
  (UNNotificationScheduler.swift:92). Harmless for delivery (iOS will not
  present while denied) but see bug list.

## Remote tuning knobs (notification-relevant)

All resolved once per launch, clamped, applied before the first re-lay
(RemoteTuning.swift:387-407, bootstrap at 507-537). Defaults mirror shipped
constants.

| Key | Default | Lands in |
|---|---|---|
| `notif_mood_pings_daily_ceiling` | 4 | `NotificationPlanner.Constants.moodPingsPerDayCeiling` |
| `notif_floor_taper` (JSON) | [4, 3, 2, 1] | `floorTaperBudgets` |
| `notif_cadence_very_sad` (JSON) | count 4, 2 h | `cadenceRules[.verySad]` |
| `notif_cadence_anxious` (JSON) | count 3, 3 h | `cadenceRules[.anxious]` |
| `notif_cadence_uneasy` (JSON) | count 1, 4 h | `cadenceRules[.uneasy]` |
| `notif_backstop_days` | 7 | `backstopInterval` |
| `notif_horizon_days` | 7 | `NotificationOrchestrator.Constants.horizonDays` |
| `notif_shh_hours` | 24 | `shhDuration` (also rendered into the shh action title) |
| `notif_recovery_hold_hours` | 24 | `TaperTracker.recoveryHold` |
| `notif_crushed_yesterday_threshold` | 5 | `NotificationCopy.crushedYesterdayThreshold` |
| `vacation_grace_decay_hours` | 24 | mood-ping post-vacation grace |
| `letter_send_weekday` / `letter_send_hour` | 1 / 19 | letter period cutoff |
| Mood engine keys (`mood_*`) | various | shape the forecast curve, so they indirectly move every mood ping |

## Bugs and risks found

Items 1, 2, 3, 5, 6, and 9's backstop gate were fixed in the 2026-08-01 fix
pass (roadmap steps 2 and 5); their entries below are kept for history with a
FIXED marker.

1. FIXED (step 2). Sign-out and account deletion never cleared the pending
   queue. Both identity exits now call `clearForIdentityExit(userId:)`, which
   removes every app-owned pending id and drops the exiting user's persisted
   scheduler state.

2. FIXED (step 2). Scheduler state was device-scoped. The taper stretch, shh
   valve, and copy deck are now keyed per uid, with legacy device-scoped
   values folded into the signed-in user's keys on first read.

3. FIXED (step 5). DST off-by-one-hour in the rundown wake time. `planRundowns`
   and the DEBUG inspector's `quietWindows` now anchor with
   `calendar.date(bySettingHour:)`, so the briefing holds its wall-clock
   promise on 23- and 25-hour days. Pinned by
   `PlannerRundownTests.rundownWallClockAcrossDST`. Bedtime CONTAINMENT was
   always wall-clock correct (UserProfile.swift).

4. Timezone changes while the app is dead are not re-laid. Timed reminders
   are documented as wall-clock intentions and the `NSSystemTimeZoneDidChange`
   observer re-lays (AppContainer.swift:292-301), but one-shot triggers are
   scheduled as absolute `UNTimeIntervalNotificationTrigger`s
   (UNNotificationScheduler.swift:39-44), so a promise laid before a flight
   fires at the OLD zone's instant until the app next runs. Repeating
   calendar-trigger promises (daily/weekly/monthly) do follow local wall
   clock. Inherent to local notifications without a relaunch hook; worth
   knowing, hard to fix fully.

5. FIXED (step 5). Monthly promises on day 29-31 silently skipped short
   months. `PromiseTriggerBuilder` now returns nil for days past 28, so those
   cadences schedule their single next occurrence (`nextOccurrence` clamps
   via `byAdding: .month`) and lean on the re-lay, like weekdays and custom
   sets. Day 28 and below keep the one-slot repeating trigger.

6. FIXED (step 5). `center.add` failures were swallowed. The adapter now
   catches and logs a `scheduleFailed(id:)` telemetry event (id prefix only,
   never a title). The relaid event still counts the plan; the failure events
   are the correction signal.

7. Mood-ping id truncates sub-second precision. `NotificationID.mood` bakes
   `Int(fireAt.timeIntervalSince1970)` (NotificationPlan.swift:74-76) while
   the trigger is built from the un-truncated date. The DEBUG inspector's
   invariant check recomputes the band at the truncated instant
   (DevSchedulerScreen.swift:276-283), so a ping laid within one second of a
   band crossing can report a false invariant violation. Cosmetic, DEBUG only.

8. `TaperState.lastFloorDay` is written but never read
   (TaperTracker.swift:20-21, 57; no consumer anywhere). Dead state, or a
   missing staleness check depending on intent: because only `firstFloorDay`
   matters, a floor stretch interrupted by weeks of uneasy-band observations
   (which never start a recovery hold) keeps counting from the original first
   day. That is documented as intended for short gaps, but a months-long
   uneasy plateau still lands the user at 1 ping/day chronic forever, which
   may or may not be the design's intent.

9. Backstop gate FIXED (step 5): the backstop is now its own genre, planned
   whenever ANY notification pref is on and silenced only by a full opt-out
   (all four genres off), vacation, or lapse. NOTE the behavior change: mood
   dips default off, so default-pref users now get the 7-day dormancy
   backstop for the first time (flagged in the roadmap's open questions).
   Still open from this item: the letter genre depends on
   `letterInputProvider` being wired; in its absence (`nil` provider, e.g.
   partial containers or tests) letters silently plan nothing with no
   telemetry.

No double-scheduling was found: ids are stable and deterministic, same-id adds
replace in place, the differ only removes ids the app owns
(NotificationPlanDiff.swift:25-31), re-lay idempotence is pinned by test
(NotificationDeliveryTests.swift:681-690), and the debounce coalesces storms
(test at line 745-758).

## Copy inventory: every string a notification can show

Every user-visible string that can render on the lock screen, verbatim from
source. `{name}` is the pet name, inserted verbatim at dress time via
`PetCopyTemplate` (NotificationCopy.swift:26-32); other `{slot}` values are
listed with their pools. Every pool rotates round-robin through a persisted
`CopyDeck` and never repeats a line until the pool cycles. Excluded here:
in-app UI text (primer, prefs, banners, celebrations on screen) and DEBUG
inspector strings, since neither ever renders inside a notification. The one
in-app pool kept for contrast is flagged.

### Mood pings (NotificationCopy.swift:66-105)

Title is always the bare pet name. Body comes from the band's pool. The
2026-08-02 string review revised uneasy line 2 and added two cute-energy
lines to the uneasy and anxious pools (the blanket-corner register); the
floor pools were deliberately left alone, since comedy at the floor risks
the "would this make a fragile person feel worse" ship test.

Uneasy pool (1/day cadence):

1. "{name} is getting a little fidgety. One small win would settle them right down."
2. "{name} keeps glancing at the list… nudge nudge."
3. "One tiny task and {name} will glow all afternoon."
4. "{name} is doing little pacing circles. They believe in you."
5. "One check-off and {name} curls right back up."
6. "{name} noticed something slipping. No rush, whenever you're ready."
7. "{name} flopped dramatically across the list. They'll recover the second you check something off."
8. "{name} is giving you the big eyes. The really big ones."

Anxious pool (3/day cadence):

1. "{name} is having a wobbly moment. They'd love some company."
2. "{name} is a little tangled up right now. A small step would help you both."
3. "Things feel heavy to {name} today. Start tiny, they'll follow."
4. "{name} is chewing on a blanket corner again. Come sit with the list together."
5. "{name} is worried, but they know you always come through."
6. "Deep breaths, says {name}. One thing at a time."
7. "{name} has burrowed into the blanket pile. Only the ears are poking out."
8. "{name} is sitting in worried loaf position. One small step would un-loaf them."

Floor acute pool (verySad, taper days 1-2):

1. "{name} is having a hard day too. Anything at all lifts you both."
2. "It's been a lot lately. {name} just wants to see you."
3. "{name} is sitting with it. One little thing, together?"
4. "Even a tiny check-in makes the day softer for {name}."
5. "Rough patch. {name} is not going anywhere."
6. "{name} saved you a spot. Whenever you're ready."

Floor chronic pool (verySad, taper day 3 and beyond; ALSO the backstop's
body, NotificationScheduling.swift:163-174):

1. "No pressure. {name} is just here."
2. "{name} is keeping your spot warm."
3. "Nothing needed today. {name} says hi."
4. "{name} is right where you left them."
5. "Quiet day. {name} is thinking of you."

### Promise reminders (NotificationCopy.swift:150-159)

Never the pet name (locked rename rule). Revised in the 2026-08-02 string
review: the title is now a generic knock and the task title moved into the
body:

- Named: title = "You have something due!", body = the task title.
- `hideTaskNames` on (or no title): title = "You have something due!",
  body = "One new task is due. Check the app to view!"

### Morning rundown (NotificationCopy.swift:166-218)

Revised in the 2026-08-02 string review: the summary never names a task
(title lists read confusing on the lock screen), it speaks in counts.

Title pool:

1. "Good morning"
2. "Good morning from {name}"

Crushed-yesterday title override: "Good morning. You crushed yesterday"

Body is two lines: a lead plus a summary. The lead is the Personal-Layer
opener when one is assigned (pools below), otherwise the cheer pool:

1. "{name} is up early and rooting for you."
2. "One thing at a time. {name} will be right here."
3. "{name} stretched, yawned, and believes in today."
4. "Slow start is fine. {name} says so."

Summary line variants ({N} = RundownRanker's totalDue at the briefing's own
fire time):

- Nothing due: "Nothing due today. {name} is taking it easy with you."
  (replaces the whole body line, still preceded by an opener if assigned)
- One: "One task is due today."
- Several: "{N} tasks are due today."

### Rundown Personal-Layer openers

One of these leads the rundown body when MemoriesService assigns a line
(crushed-yesterday is a title override, not an opener). Counts are spelled
words (LetterCopy.numberWord), never digits.

Anniversary (MemoriesCopy.swift:26-31; {span} = "One week" / "One month" /
"One year" / "Two years"...):

1. "{span} with {name} today."
2. "Today makes {span} of you and {name}."
3. "{span} together as of today. {name} kept count."
4. "{span} since you and {name} met."

Deferred anniversary, mark passed on vacation (MemoriesCopy.swift:36-41;
{mark} = "one-week" / "one-month" / "one-year" / "two-year"...):

1. "While you were away, you and {name} passed the {mark} mark."
2. "Somewhere out there, you and {name} crossed the {mark} mark."
3. "The {mark} mark slipped by during your time away. {name} counted it anyway."
4. "You and {name} passed the {mark} mark while you were off resting."

Best-day callback (MemoriesCopy.swift:56-61; {when} = coarse relative time,
{count} spelled, {scale} = "your biggest day" or "one of your biggest days"
on a tie):

1. "{when} you cleared {count} things in one day. {name} still talks about it."
2. "{name} remembers {scale}: {count} things, one day, {when}."
3. "Remember {when}, when {count} things got done in a single day? {name} does."
4. "{count} in one day, {when}. {name} filed it under favorite memories."

Recovery callback (MemoriesCopy.swift:68-74; structurally restricted: {name}
is the only slot, no counts, no "back to" / "used to", no reference to the
present pile):

1. "You've found your way through a pile before. {name} remembers."
2. "You've dug out before. {name} never doubted it."
3. "There was a stretch that looked heavy, and you cleared it. {name} keeps that story."
4. "You've done this before. {name} was there for it."
5. "{name} has watched you climb out before. That memory stays."

Streak era, count-only (MemoriesCopy.swift:77-82):

1. "Your longest run with {name} is {count} days."
2. "{count} days in a row, once. {name} still brags about it."
3. "The record stands at {count} days together. {name} keeps it polished."
4. "{count} straight days, your best yet. {name} remembers every one."

Streak era, dated (MemoriesCopy.swift:86-91):

1. "Your longest run together, {count} days, wrapped up {when}. {name} was there for all of it."
2. "{when} you set the record: {count} days straight. {name} still talks about that stretch."
3. "The {count}-day record you set {when} still stands. {name} guards it proudly."
4. "{count} days in a row, {when}. {name} calls it the golden stretch."

Date echo (MemoriesCopy.swift:96-101; {monthsago} = "A month" / "Two
months"...):

1. "{monthsago} ago today you finished {count} things. {name} remembers the date."
2. "{monthsago} ago today, {count} things done. {name} circled it on the calendar."
3. "{monthsago} ago today you had one of those days: {count} finished."
4. "{name} keeps an eye on dates. {monthsago} ago today: {count} things, done and dusted."

Coarse relative time slot values (MemoriesCopy.swift:135-143): "about a week
ago", "a couple of weeks ago", "about a month ago", "a couple of months
ago", "a while back".

Observation openers (ObservationCopy.swift; qualitative by locked rule, no
counts or numbers ever). Weekday pool ({weekday} = "Sundays"..."Saturdays"):

1. "You get the most done on {weekday}. {name} noticed."
2. "{weekday} are your days. {name} keeps notes on these things."
3. "Something about {weekday} suits you. {name} has been paying attention."
4. "{name} thinks of {weekday} as your day now."

Morning band:

1. "Mornings are when things happen around here. {name} noticed."
2. "You and mornings get along. {name} keeps notes."
3. "The early hours are yours. {name} has seen it enough to be sure."
4. "{name} noticed the day's wins tend to come early."

Afternoon band:

1. "Afternoons are when things happen around here. {name} noticed."
2. "You hit your stride after lunch. {name} keeps notes."
3. "The middle of the day is yours. {name} has seen it enough to be sure."
4. "{name} noticed the afternoon is where your day comes together."

Evening band:

1. "Evenings are when things happen around here. {name} noticed."
2. "You wind the day down by getting things done. {name} keeps notes."
3. "The evening is yours. {name} has seen it enough to be sure."
4. "{name} noticed your day comes together in the evening."

Night band (affirms, never corrects):

1. "Things get done after 9pm around here, and that counts just the same. {name} noticed."
2. "The late hours are yours. {name} thinks that's a fine time for them."
3. "{name} noticed the quiet hours are when you get things done. No notes, just admiration."
4. "Night is when your list gets shorter. {name} keeps you company either way."

Momentum rising:

1. "More check-offs lately. {name} can feel it."
2. "Things are moving around here. {name} noticed."
3. "{name} can tell something's picked up lately."
4. "The list has been shrinking faster. {name} is quietly delighted."

List return ({list} = the list's name; celebrates the return, never the
absence):

1. "You found your way back to {list} this week. {name} noticed."
2. "{list} got some attention this week. {name} was glad to see it."
3. "Back to {list} this week. {name} likes seeing that one move."
4. "{name} noticed {list} moving again this week."

Comeback:

1. "When something slips, you catch it fast. {name} loves that about you."
2. "{name} noticed you always circle back. It never takes you long."
3. "Slipped things don't stay slipped around you. {name} keeps notes."
4. "You have a way of catching things quickly. {name} admires it."

### Weekly letter invitation (NotificationCopy.swift:107-112, 220-227)

Title: "A letter from {name}". Body pool:

1. "{name} wrote you a letter about the week. It's waiting whenever you are."
2. "There's a letter from {name} on the mat. No rush at all."
3. "{name} put the week into words. Come read when it suits you."
4. "A little envelope from {name} is waiting inside."

### Backstop

No copy of its own: title = pet name, body drawn from the floor chronic pool
above (pure presence, no ask, safe at any staleness).

### Action button labels

Reminder category (UNNotificationScheduler.swift:118-127,
SnoozeOption.swift:22-28):

- "Complete"
- "Snooze · In 1 hour"
- "Snooze · Tonight" (19:00, or an hour out if already evening)
- "Snooze · Tomorrow" (09:00)

Mood-ping category (UNNotificationScheduler.swift:129-145,
NotificationActionTitles.swift:21-30). The pet name is included only while
it fits a ~12 character render-width budget (CJK and emoji weighted double);
{h} is the remote-tunable shh duration, default 24:

- "Pet {name}", falling back to "Pet"
- "{name}, shh · {h}h", falling back to "Shh · {h}h"

### Dormant and adjacent pools (not notifications today)

`celebrationPool` (NotificationCopy.swift:115-121) has no consumer anywhere;
celebrations are in-app only. Kept in the file, listed here since it would
become lock-screen copy if ever wired:

1. "{name} is doing a happy dance! 🎉"
2. "Look at you go. {name} is beaming."
3. "{name} squeaked with joy!"
4. "That streak though. {name} is so proud. ✨"
5. "Confetti everywhere. {name} insisted."

`anniversaryBannerPool` (MemoriesCopy.swift:43-48) is the in-app banner
sibling of the anniversary rundown pool, listed for voice comparison only:

1. "{span} with {name} today."
2. "{span} of you and {name}. Happy day."
3. "Today marks {span} together. {name} is glowing."
4. "{span}, as of today. {name} remembered the date."
