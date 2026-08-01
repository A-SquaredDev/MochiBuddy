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
- Copy: names the task ("Due now. Rooting for you."); the `hideTaskNames`
  privacy pref swaps a nameless variant (NotificationCopy.swift:142-150).
  Promise copy never embeds the pet name, the locked rule that lets renames
  leave promises untouched (verified by test, NotificationDeliveryTests.swift:498-524).
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
- Content (NotificationRequestBuilder, NotificationScheduling.swift:109-152):
  top 1-3 tasks ranked at the rundown's own fire time with recurrence rolled
  forward: overdue by lateness descending, then due-today timed by time, then
  due-today date-only by priority (RundownRanker.swift:14-44).
- Title flexes to load: "One thing today" / "A light day today" / "Big one
  today. We've got this" / "A calm day"; a notably productive yesterday
  (5 or more completions, a COUNT never an effort-weighted sum) takes over the
  title as "You crushed yesterday" (NotificationCopy.swift:154-199).
- Personal Layer: one line per rundown morning (streak milestone, anniversary,
  crushed yesterday, memory callback, or observation, in that canonical
  priority) is assigned for the whole horizon in one deterministic pass by
  MemoriesService and leads the body as an opener
  (NotificationOrchestrator.swift:229-238, AppContainer.swift:183-191,
  MemoriesService.swift:81-149).
- `hideTaskNames` swaps in "Your top N tasks are ready when you are".
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
