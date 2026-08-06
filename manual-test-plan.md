# MochiBuddy manual test plan

A physical walkthrough for a human tester. Each item is an action, what
you should see, and the ifs and buts that change what you see. No code
knowledge needed. Work top to bottom; later sections assume earlier ones
passed. Check items off as you go.

**Setup you need:** an iPhone with the TestFlight build, notification
permission decisions of your own choosing (the plan calls out both paths),
and ideally two sessions a few days apart - several features only come
alive with history (letters, observations, memories, suggested times).
Those are marked **[needs history]** with what to expect in the meantime.

**Known placeholders, not bugs:** app icon art is a rough render, the
launch screen is plain, Privacy Policy and Help links point at a site that
is not live yet. Do not file these.

**When something is wrong,** write it in `bugs.md` rather than in the
margins of this plan. The bug log page, `tools/bug-log.html`, is the
comfortable way to do that: it takes the area, severity, steps, expected,
and actual, then saves the whole log back to `bugs.md`. A one-line note on
the item here is still fine for small observations.

---

## 1. Onboarding and sign-in

- [ ] Fresh install → launch. Onboarding flow appears (not the main app).
- [ ] Sign in with Apple works. **But:** Apple only shares your name on the
  very first authorization ever; on a re-install the display name may be
  blank. That is expected - it is editable later in You.
- [ ] Sign in with Google works (browser sheet, returns to the app).
- [ ] Meet Mochi naming step: you can name the pet or skip.
  - **If** you name it: the very next screen already uses the name.
  - **If** you skip: the pet is "Mochi" everywhere.
  - **Either way** the adoption date is stamped today and appears later in
    You ("Met on ...") and as the Journal's first moment.
- [ ] Name field: try a 30-character name - it caps at 16 visible
  characters. Try emoji-only and spaces-only - it never saves an empty or
  whitespace name.
  - **An emoji-only name is allowed and is by design** ("it's their pet").
    The sanitizer strips control and bidi characters, caps at 16
    graphemes, and falls back to "Mochi" only when nothing printable is
    left. Do not file emoji names.
- [ ] Paywall shows real localized prices for monthly and annual.
  **But:** on a bad network it shows fallback prices ($3.99 / $29.99) -
  acceptable, retry on good network.
- [ ] Sign out (You tab) and sign back in: you land in the app, not
  onboarding, with your data intact. The pet name and adoption date
  survive.
- [ ] Sign out lands on the Landing screen (not the splash spinner), and
  no new anonymous user appears in the Firebase Auth console. Same after
  deleting an account. "Let's get started" from there still walks the
  wizard and saves choices normally.
- [ ] Sign in with an already-used Apple/Google account from a fresh
  install: you land in your existing account, and the throwaway anonymous
  user that splash created is deleted from the Firebase Auth console
  (not left behind).
- [ ] Delete the app, reinstall, sign in: everything returns from the
  server (tasks, name, streak, letters).
- [ ] **Nameless Apple account gets asked, and must answer.** Apple hands
  over a display name on the first-ever authorization only, so an account
  whose profile has none must be asked rather than left as "Mochi friend".
  (Revised 8/5: the sheet is now required - the original "Not now" exit
  was cut.)
  - Setup: delete the account from inside the app (You → Delete account),
    then sign in again with the same Apple ID. Apple will not resend the
    name.
  - On reaching Home, a sheet asks "What should {PetName} call you?" with a
    one-line explanation, a name field, and Save.
  - The sheet cannot be dismissed: no skip link, and dragging it down does
    not close it. Save stays disabled until the field has a non-blank name.
  - Save: the name appears immediately in the You identity row and the Home
    greeting, and the sheet never returns.
  - It must never appear for an account that already has a name (including
    Google sign-in, which does send one).

## 1b. Done tab pagination

Seed data (DEBUG builds): You → Scheduler inspector → Test fixtures →
"Seed done-history fixture" writes 36 completions across 4 recent days,
enough to force page two and an uncapped week count. Its "How to use"
sheet has the full walkthrough (Pass 3). Delete fixtures when done.

- [ ] Tasks → Done: the timeline loads and scrolling near the bottom
  quietly loads older history (shimmer rows, then more days). The "Load
  older" button does the same with VoiceOver.
- [ ] With more than 30 completions, "N done this week" shows the exact
  count, not a capped number. In airplane mode it falls back to counting
  the loaded rows and never shows zero wrongly.
- [ ] Scrolling past a month boundary shows the "JULY 2026" divider.
- [ ] Reaching the very end shows "That's the whole story since you
  adopted {pet}" and no spinner.
- [ ] Airplane-mode load-more: the shimmer resolves without a crash and
  the end-of-history footnote is not shown falsely.
- [ ] A list's detail screen shows that list's own recent completions
  even right after completing many tasks in other lists. (Requires the
  console composite index: tasks · listId ASC, completedAt DESC. Until
  it exists this falls back to the old behavior.)

## 2. Home

- [ ] Greeting uses your display name; the mood line and pet references use
  the pet's name.
- [ ] The pet is drawn and animated. Tap the Pet button: a small happy
  reaction and the comfort meter bumps up. Repeated petting keeps bumping
  but the meter has a cap.
- [ ] Quick add: type a task and hit return. The field clears, the task
  appears in Today immediately.
- [ ] Plus button opens the full editor prefilled for today.
- [ ] Complete a task from Home: row moves to Done today, coins go up by
  10, the coin pill updates. Undo the completion: the coins come back off.
- [ ] Today shows all of today's tasks in a timeline; Done today and This
  week sections render below.
- [ ] Mood reacts to your list: overdue tasks pull the mood down over
  time; completing things and petting push it up. **But:** mood never
  changes instantly to sad - it decays gradually.
- [ ] **If** the current time is inside your bedtime window (You →
  Bedtime): the pet is asleep and stays asleep until the window ends.
- [ ] **If** you complete the task that lands a streak milestone (7, 30,
  then every 50): a celebration banner appears at that moment, and is
  dismissible. It does NOT appear for ordinary completions.
- [ ] **If** an unread letter exists (Sundays onward, see section 9): a
  quiet envelope indicator shows on Home. Tapping it opens the letter
  inside the Journal tab.
- [ ] **If** today is an adoption anniversary (1 week, 1 month, then
  yearly): a banner on first open of the day. **But:** if a streak
  milestone lands the same day, the streak banner wins and the anniversary
  stays quiet (the weekly letter will still mention both).

## 3. Tasks tab

- [ ] Four segments switch correctly; counts match reality.
- [ ] Lists: tapping a list row pushes a list detail screen scoped to that
  list.
- [ ] Done: a per-day timeline of completions. A coin banner sums the day;
  its X dismisses it for that day only (it returns tomorrow).
- [ ] Completing and un-completing from this tab moves coins exactly like
  Home does. Streak and coins agree across Home, Tasks, and You.
- [ ] **If** Apple Reminders lists are synced (You → Apple Reminders):
  imported rows appear alongside Mochi tasks. Completing one checks it off
  inside the Apple Reminders app too. **But:** Reminders completions earn
  no coins, and tapping a Reminders row never opens the Mochi editor.
- [ ] **Re-time badge [needs history]:** a recurring task with a time that
  you habitually finish hours away from its due time shows a small clock
  glyph with a circling arrow on its row, in the accent color. Tapping the
  row opens the editor with the re-time suggestion visible.
  - Seed data (DEBUG builds): You → Scheduler inspector → Test fixtures →
    **"Seed re-time fixture (9:00 series done at 19:00)"** builds a daily
    "[Seed] Daily review" whose eight past occurrences (due 9:00 AM) were
    finished around 7:00 PM, plus one live occurrence due tomorrow.
  - The rule it is exercising: recurring **and** timed, 8+ timed
    completions across 5+ distinct dates, habitual finish 3+ hours from
    the due time.
  - In the editor expect the chip "This usually gets done around 7:00 PM."
    with "Tap to change its due time from here on." Tapping it fills 7:00
    PM and the chip goes quiet ("7:00 PM set"). Save, and the badge
    clears; the NEXT occurrence carries 7:00 PM too.
  - Dismissing the chip (small x) keeps it gone unless a later proposal
    differs by an hour or more.
  - Delete fixtures when done - they write real completions that Stats,
    Best hours, Done, and Journal will all see.
  - It appears on the Tasks tab and inside a list, and **never on Home's
    today list** and never on a Reminders row. That is deliberate.
  - A row that is both due soon and badged shows the warning clock AND the
    accent badge, and the two must stay visually distinct. Check all five
    flavors.
  - Long title plus badge plus list dot plus priority chip on a small
    phone: the title truncates, nothing wraps or clips.
  - Dismissing the suggestion in the editor removes the badge next time
    you visit the list.
  - Scrolling a long list stays smooth (the check runs once per load, not
    per row).

## 4. Task editor

- [ ] New task: title field is focused with keyboard up. Editing an
  existing task: keyboard stays down until you tap a field.
- [ ] Set date, time, priority, list, notes, repeat - all persist after
  save and survive an app restart.
- [ ] Repeating task: complete it (anywhere - Home, Tasks, notification,
  widget). Exactly one next occurrence appears at the next due date. Never
  two.
- [ ] **Delete always asks first.** Deleting is the only irreversible thing
  the editor does, and there is no undo behind it.
  - A one-off task: "Delete this task?" with a destructive Delete and a
    Cancel. Cancel leaves the task untouched; Delete removes it and closes
    the editor.
  - A repeating task **with** a due date: the older skip-vs-series dialog
    instead ("Skip this occurrence" / "Delete the series").
  - A repeating task with **no** due date: there is no occurrence to skip,
    so it gets the plain confirm, whose message says the series stops.
    (This case used to delete on the first tap.)
- [ ] **Dated but untimed task names its reminder time.** Set a date, leave
  the time unset: a line under the time pill reads "Reminds at 9:00 AM",
  or whatever You → Notifications → default reminder time is actually set
  to. Change that default and reopen the editor: the line follows it. Set
  a time on the task and the line disappears.
- [ ] **Suggested time chip [needs history]:** with 3+ weeks of completions
  that cluster at a consistent time, opening a new task's time picker area
  shows a one-line suggestion chip with a reason.
  - Seed data (DEBUG builds): You → Scheduler inspector → Test fixtures →
    **"Seed new-time fixture (18 evening completions)"** writes 18
    completions around 7:00 PM across six past days into a "Seeded
    fixtures" list. Then make a new task on that list due **TOMORROW**
    with no time set. (Tomorrow, not today: a task due within 30 minutes
    of the proposal is silenced by the lead-time guardrail, and 7:00 PM
    may already be past.)
  - The rule it is exercising: roughly 15 completions across 5+ distinct
    dates inside 42 days, clustering in a ±90-minute window.
  - **If** your bedtime window covers 7:00 PM the chip stays silent by
    design. Move bedtime before deciding it is broken.
  - The Suggestions inspector on the dev screen shows each gate passing or
    failing for that scope (evidence, dates, peak share, runner-up) if you
    want to see why a chip did or did not appear.
  - Delete fixtures when done.
  - **If** your history is spread out or split between two times of day:
    NO chip. Absence is correct behavior, not a bug.
  - **If** you dismiss the chip: it stays gone for that task, and a new
    suggestion needs a meaningfully different time (an hour or more) to
    reappear.
  - Accepting fills the time; changing the time by hand afterwards is
    always allowed.
  - The chip must never appear while lapsed, never for an Apple Reminders
    item, and never suggest a time in the past or inside bedtime.
  - **If** your history is split between weekdays and weekends: the chip
    can still appear, worded "On Tuesdays you usually wrap up in the
    evening." That wording only shows for a weekday-specific pattern; it
    must never appear on a general suggestion.
- [ ] **Effort:** the Priority row carries a second control on the right
  under its own EFFORT label. Unset it reads "Set effort"; tapping opens a
  menu of Tiny, Small, Medium, Large, and Clear.
  - **No clock times anywhere in that menu.** If you see minutes or hours,
    file it.
  - On a small phone (SE class) the priority chips may wrap within their
    own block, but the effort pill must not fall to its own full-width row.
  - With priority "Med" AND effort "Medium" both set, the row should still
    read as two separate questions. If it reads as a duplicate, say so.
  - The rating persists across save and restart, and a repeating task
    passes it to its next occurrence.
  - VoiceOver announces "Effort: Medium" or "Set effort".
- [ ] **Effort and Mochi's mood [needs two accounts or two days]:**
  complete one Large task, versus three unrated tasks. The mood lift
  should look comparable. Coins must be identical either way (effort never
  changes coins). Rating something Tiny versus leaving it blank must have
  no effect at all.
- [ ] Overdue behavior: a long task overdue does NOT stress Mochi more
  than a short one at the same priority. Effort only counts on the credit
  side.
- [ ] Push counting: move an incomplete task's due date to a **later** day
  from the editor. Moving it earlier, or changing only the time, must not
  count as a push. (There is no user-visible surface for this yet; it is
  feeding a future feature, so this only matters if you are checking data.)
  - What it feeds: a "push" increments `rescheduleCount` on the task, the
    procrastination signal specced for v2 and landed early so it can
    accumulate real evidence before the feature ships. Its one live
    consumer today is the suggested-time engine, which weights a
    completion up to 3x when the task was repeatedly pushed - a task you
    kept moving says more about when work actually happens.
  - Snooze counts as a push too. Skipping a recurring occurrence and
    vacation triage deliberately do not - different intents.
  - Nothing renders it, so this is a data check, not a UI check. The
    negative cases (moving earlier, re-timing within the same day, adding
    or clearing a date, a completed task) are pinned by
    `TaskEditorViewModelTests`; treat those as covered by test rather than
    re-deriving them by hand.

## 5. Journal tab

- [ ] Brand-new account: the Journal shows a single adoption moment ("The
  day your story began" or your named copy) - no empty charts, no
  placeholders.
- [ ] With activity: a timeline grouped by month mixing letters and
  moments (adoption, streak milestones, anniversaries, returns).
- [ ] **If** an unread letter exists: it is promoted to a hero card up top;
  tapping opens the detail. Once read, it returns to its place in the
  timeline and the unread styling clears.
- [ ] **If** the engine has noticed a pattern **[needs history]**: a card
  of one to three lines in the pet's voice ("Mornings are when things
  happen around here..."). Lines are qualitative - if you ever see a
  number or percentage in this card, file it.
- [ ] Footer: week strip with per-day counts, done-this-week count, best
  streak (hidden at zero), and a 4-week trend that only appears once you
  have two distinct weeks of history.

## 6. You tab and settings

- [ ] Identity row: avatar letter, display name, email. Pencil edits the
  display name. Mochi+ badge shows when subscribed.
- [ ] Flavor swatches: pick each of the five. The whole app re-themes
  immediately AND the home-screen app icon changes to match. **But:** on
  a slow device the icon change can lag a few seconds; it should
  self-correct by next launch at the latest.
- [ ] Bedtime: change the window; Home's sleeping pose and notification
  quiet hours follow it.
- [ ] The care card holds Bedtime and nothing else. There is no Sound
  toggle (removed for v1: nothing in the app plays audio) and no Morning
  rundown toggle (it now lives only in Notification settings; the
  Notifications row's subtitle names it when it is on).
- [ ] Your Mochi card: shows name and "Met on <date>". Rename: the new
  name propagates immediately to Home greeting, mood lines, You header,
  notification action labels, the widget, and future notification copy.
  Rename works even while lapsed.
- [ ] **Streaks & stats** row opens the stats screen:
  - Range picker at the top: Week, Month, 3 months. Every card below
    follows it, and switching back and forth is instant (no reload).
  - Streak card: current streak, encouragement line, 7-day strip whose
    per-day counts match your actual completions.
  - Tiles: Done this week, On time this week, Best streak, Days together
    counting from the adoption date, and Effort. **If** the profile has no
    adoption date (very old account), a Coins tile shows instead.
  - Effort tile: an approximate total like "~3h" with a coverage subtitle
    ("12 of 34 rated"). A dash until you have rated anything. It counts
    repeating tasks too, unlike the Best hours cards below.
  - Last 4 weeks bar chart with an on-time caption. There should be **no**
    "busiest on <weekday>s" clause any more; Day by day replaced it.
  - Where tasks got done: per-list bars, biggest first, more than five
    lists folds the rest into Other. A deleted list's completions show as
    "Former list".
  - **If** the engine has noticed patterns / mined memories
    **[needs history]**: "has noticed" and "Worth remembering" cards
    appear. Under about 3 weeks of use both are correctly absent.
- [ ] **Your best hours** card (the histogram):
  - Appears as soon as you have any completions at all. A brand-new
    account sees neither this nor Day by day.
  - The clock runs 5am to 5am, so a 2am completion sits at the far right
    reading as "late", not clipped off. On a normal schedule the right
    quarter of the card is empty. That is intended, not a bug.
  - Two tiles: a PEAK range ("10a to 1p") and IN WINDOW as a percentage.
  - Mochi's line under the chart is qualitative and names a time of day
    (morning / afternoon / evening / night), never a clock time and never
    a percentage. If you see a number in that line, file it.
  - The "second wind" clause only shows up when there is a genuine second
    cluster. A small bump should not earn one.
  - A daily repeating chore must NOT drag the peak toward its time. A
    burst of one-off completions should.
  - After changing your device timezone, the bars stay put. Completions
    render in the zone where they happened.
- [ ] **Day by day** card (seven weekday rows):
  - Hidden entirely on the Week range, even when Month shows it.
  - Its 12p / 6p / 11p gridlines line up with the histogram above it. The
    two cards should read as a matched pair. **Every axis label gets a
    hairline** - three labels, three lines. (Before the gridline fix the
    card drew only 12p and 6p; if you still see two lines, the fix has
    not landed in your build.)
  - A weekday with little data shows only a small dot, no capsule. Once a
    day has real history it gains the middle-half capsule and the range
    line.
  - Mochi's line names the actually-quiet days, folding Saturday and
    Sunday into "the weekend" when both are thin.
  - Day picker: the pill under the eyebrow lists every day that has data.
    Picking one swaps the middle of the card for that day's own hour
    curve; "All days" returns to the seven rows.
  - Pick a thin day: you get bars and a "still learning" line, with NO
    tiles and no highlighted peak. Two data points must never produce
    "100% in window".
  - Changing the range while a day is picked returns you to All days.
- [ ] The "?" on both card headers opens **About these charts**. Its
  swatches should match the real card marks. Going back preserves your
  range and day selection.
- [ ] Both cards, the day picker, and the help screen in **all five
  flavors**. Watch specifically for the IN WINDOW value and any tinted
  text on the inner card surface staying readable outside Black Sesame.
- [ ] On a 320pt device (SE class) the tiles do not wrap and the legend
  stays on one line.
- [ ] VoiceOver: the histogram reads its peak range and in-window share as
  one summary; each Day by day row reads its typical time or "still
  quiet"; the day pill announces "Day filter".
- [ ] Notifications screen: per-category toggles (reminders, mood pings,
  rundown, weekly letter). Turning one off actually stops that category
  (verify over a day or two).
- [ ] Apple Reminders: granting access lists your Reminders lists; chosen
  lists sync read-only into Tasks. Deny access: the screen degrades
  politely, no crash.
- [ ] Manage lists: create, rename, recolor, delete. Deleting a list does
  not delete its completion history (see "Former list" above).
- [ ] Manage subscription opens Apple's subscription page. Restore
  purchases spins, then reports found or not found honestly.
- [ ] Footer reads "Mochi {version} · Made with care" and the version
  matches the build you are testing. The version comes from
  CFBundleShortVersionString, so it needs no per-release edit. There is no
  age rating in the footer: it was a hardcoded "Rated 4+" that could not
  track App Store Connect.

## 7. Notifications

Grant permission when asked. **If** you decline: the app must keep
working fully; notification-dependent items below simply will not fire,
and the Notifications settings screen should reflect the denied state.

- [ ] Task reminder arrives at due time. Its Complete action completes the
  task (coins land, next occurrence spawns if repeating) without opening
  the app. Snooze options reschedule it.
- [ ] Morning rundown arrives in the morning with a ranked summary.
  - Setup: You → Notifications → Morning rundown ON, at least two open
    tasks due today or overdue, then background the app.
  - Same evening, check the dev Scheduler inspector (You → Scheduler
    inspector, DEBUG builds): the forecast / pending queue should already
    hold a rundown entry for tomorrow morning. If it is missing there it
    will not arrive - note what the inspector shows instead of waiting.
  - Next morning expect exactly one rundown, count-style ("3 due today"),
    with no task titles if the hide-task-names privacy toggle is on.
    Tapping it opens the app.
  - It must never land inside your bedtime window, and toggling the
    setting OFF must remove the queued entry from the inspector.
  - **If** you finished 5+ tasks yesterday: the title celebrates it.
  - At most ONE personal line ever rides a rundown (a streak note, an
    anniversary, a memory callback, or an observation) - never two.
- [ ] Mood pings: when tasks pile up overdue, a gentle ping in the pet's
  voice. Never more than 4 in a day, never inside bedtime or quiet hours.
  - Pet action bumps the comfort meter from the notification.
  - Shh action silences mood pings for 24 hours - verify nothing mood
    related arrives in that window.
  - **If** things stay bad for days: pings get LESS frequent (4/3/2/1
    taper), not more. Recovery (a day fully held) resets the cadence.
- [ ] Notification copy: pet name renders correctly everywhere, emoji only
  in celebration moments, and if you enabled the "hide task names"
  privacy toggle, task titles never appear on the lock screen.
- [ ] Letter invitation (Sunday): one notification, tapping it lands
  directly on the letter inside Journal.

## 8. Widgets

- [ ] Long-press home screen → add Mochi widgets: small and medium exist,
  plus lock screen sizes.
- [ ] The widget shows the pet and comfort/mood state consistent with the
  app.
- [ ] Pet button on the widget bumps the comfort meter; the app agrees
  when opened.
- [ ] Complete button on the widget checks a task off. **But:** coins land
  on next app open, not instantly on the widget - that is by design.
- [ ] Rename the pet in the app: the widget picks the name up on its next
  refresh.
- [ ] **If** lapsed or on vacation: the widget switches to a matching
  quiet state instead of pretending everything is normal.

## 9. Weekly letter [needs history - runs on real calendar weeks]

- [ ] The first letter can only cover your first FULL Monday-to-Sunday week
  after adoption. Before that, no letter and no envelope - correct.
  - **The rule in one sentence:** your first letter arrives at 7 PM on the
    Sunday of the week AFTER your adoption week. So a Sunday adopter waits
    7 days, a Monday adopter 13, a Wednesday adopter 11.
  - Deliberate wrinkle: if you adopt on a Sunday, anything you complete
    after 7 PM that same evening falls inside the following week and so
    lands in that first letter.
- [ ] Sunday (from the send hour onward), open the app: a letter composes.
  Envelope on Home, hero in Journal, invitation notification (if that
  toggle is on).
- [ ] The letter reads like the week you actually had (rough weeks get a
  gentler letter; quiet weeks a shorter one). It mentions a streak
  milestone or anniversary if the week had one.
- [ ] Read it: unread indicators clear everywhere and stay cleared on
  other days.
- [ ] Share: the share card defaults to the private variant; a full
  variant is offered per share. **If** it was a rough week: only the
  private card is offered. Save to Photos works (first time asks photo
  permission).
- [ ] **If** the whole week was vacation, or you did nothing all week
  after week one: no letter for that week. Absence is correct.

## 10. Vacation mode

- [ ] You → Vacation mode: date picker defaults one week out; open-ended
  is allowed.
- [ ] While on vacation: Home shows a vacation banner and a resting pet,
  mood UI is hidden, no mood pings or rundowns arrive (task reminders you
  explicitly set still do).
- [ ] End now (or the end date passing), then open the app:
  - **Three ways out:** the Home banner's "End now", the day-14 card's
    "Welcome me back", or You → Vacation mode → "Turn off & catch up".
    No seed data needed; the whole pass takes about ten minutes.
  - **Path A (end from Home).** Note your streak in You. Make a one-off
    task due today, 2 to 3 minutes out, and do not complete it. Turn
    vacation on (default end date is fine). Wait for the due time to
    pass, then tap **End now** on the Home banner. Expect, in this order:
    the banner disappears, then the triage sheet - Mochi at content,
    "Welcome back!", "Here's what came due while you were away", your
    task with Complete / Reschedule / Dismiss, plus "Reschedule all to
    this week". After you pick, the mood meter is back, Mochi is awake at
    roughly content (a 24h grace, not instantly ecstatic), the streak
    matches what you noted, and the Journal has a new moment "You and
    Mochi picked back up." dated today.
  - **Path B (end from You).** Same setup, but end via You → Vacation
    mode. Nothing dramatic happens on the You screen - the triage sheet
    appears on your NEXT visit to Home. That deferral is by design.
  - **Path C (nothing came due).** Start and immediately end a vacation
    with nothing falling due in between: no sheet at all. That silence is
    correct.
  - **If** one-off tasks went overdue during the vacation: a triage sheet
    lists them with complete / reschedule / dismiss, per-row and bulk.
    Later defers the sheet.
  - **If** nothing went overdue (only recurring items): NO sheet.
  - Each per-row action confirms itself with a snackbar naming the task
    ("Completed X", "Rescheduled X to Thu", "Dismissed X" with Undo).
    Reschedule spreads the pile across the next few days rather than
    stacking it all on tomorrow, so the snackbar must name the day it
    actually picked. A row that just vanishes with no confirmation is a
    bug (BUG-014).
  - Your streak survived the vacation, and the pet's mood does not
    punish you - the comfort buffer eases you back over the first day.
- [ ] Open-ended vacation: around day 14 a gentle check-in asks if you are
  still away. At 30 days it ends itself.
  - **Pass by unit test, not by hand.** `VacationReentryTests` and
    `MoodForecastTests` cover the 30-day cap ending an open-ended trip,
    the check-in coming due at 15 days and not at 10, never firing for a
    fixed end date, the snooze path, and the Home surface integration.
    There is no way to reach either one manually; do not sit on it.

## 11. Membership states

- [ ] Active subscriber: full app, Mochi+ badge in You.
- [ ] **Lapsed** (subscription expired): the app degrades to a quiet
  checklist - tasks still work, but the pet sleeps, mood/celebrations
  pause, flavors lock, and You shows a Wake Mochi card. Account, legal,
  sign out, delete, and pet rename all still work. Only promise-type
  notifications continue. Journal shows the frozen record, and the
  Streaks & stats row is hidden while asleep.
- [ ] Wake Mochi → resubscribe path works and everything resumes,
  including history recorded while lapsed.
- [ ] **Billing grace** (payment failed but still entitled): app fully
  works plus a fix-payment nudge line in You.
- [ ] Restore purchases on a fresh install with an active subscription
  entitles without repurchase.

## 12. Account deletion

- [ ] You → Delete account: warning screen first; **if** a subscription is
  active, an extra screen explains deletion does not cancel the Apple
  subscription.
- [ ] Deletion requires reauthentication, then erases data and lands you
  at onboarding.
- [ ] Sign in again as a NEW account afterwards: nothing from the old
  account leaks in (no name, no streak, no letters, no "noticed" lines).
- [ ] Known gap: the RevenueCat customer record is not deleted (needs a
  server function). Do not file.

## 13. Offline and multi-device

- [ ] Airplane mode: browse, add, complete, rename - everything works
  against the local cache with no spinners hanging and no crashes. Back
  online: it all syncs up.
- [ ] Force-quit immediately after completing a task, relaunch: the
  completion and coins survived.
- [ ] **If** you run two devices on one account: tasks, coins, streak,
  letters, and the pet name converge on both. **But:** the comfort meter
  is per-device on purpose - do not file meter differences.

## 14. Cross-cutting polish passes

- [ ] Dark and light appearance across every screen (Black Sesame is the
  dark theme).
- [ ] Largest Dynamic Type size: Stats tiles, letter text, editor chip,
  and notification settings all wrap instead of truncating.
- [ ] VoiceOver spot-check: Home pet controls, a task row, the week strip
  on Stats (each day announces its count), the rename field.
- [ ] No copy anywhere uses em dashes; no UI emoji outside celebration
  notification moments; the pet name the user chose renders wherever
  "Mochi" would appear, while brand surfaces ("Mochi+") stay literal.
- [ ] Rotate through a full day: no notification arrives inside bedtime,
  quiet hours drop pings rather than moving them to odd times.
