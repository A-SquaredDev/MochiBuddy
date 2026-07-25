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
- [ ] Paywall shows real localized prices for monthly and annual.
  **But:** on a bad network it shows fallback prices ($3.99 / $29.99) -
  acceptable, retry on good network.
- [ ] Sign out (You tab) and sign back in: you land in the app, not
  onboarding, with your data intact. The pet name and adoption date
  survive.
- [ ] Delete the app, reinstall, sign in: everything returns from the
  server (tasks, name, streak, letters).

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

## 4. Task editor

- [ ] New task: title field is focused with keyboard up. Editing an
  existing task: keyboard stays down until you tap a field.
- [ ] Set date, time, priority, list, notes, repeat - all persist after
  save and survive an app restart.
- [ ] Repeating task: complete it (anywhere - Home, Tasks, notification,
  widget). Exactly one next occurrence appears at the next due date. Never
  two.
- [ ] Delete task works and is confirmed.
- [ ] **Suggested time chip [needs history]:** with 3+ weeks of completions
  that cluster at a consistent time, opening a new task's time picker area
  shows a one-line suggestion chip with a reason.
  - **If** your history is spread out or split between two times of day:
    NO chip. Absence is correct behavior, not a bug.
  - **If** you dismiss the chip: it stays gone for that task, and a new
    suggestion needs a meaningfully different time (an hour or more) to
    reappear.
  - Accepting fills the time; changing the time by hand afterwards is
    always allowed.
  - The chip must never appear while lapsed, never for an Apple Reminders
    item, and never suggest a time in the past or inside bedtime.

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
- [ ] Morning rundown and Sound toggles persist across restarts.
- [ ] Your Mochi card: shows name and "Met on <date>". Rename: the new
  name propagates immediately to Home greeting, mood lines, You header,
  notification action labels, the widget, and future notification copy.
  Rename works even while lapsed.
- [ ] **Streaks & stats** row opens the stats screen:
  - Streak card: current streak, encouragement line, 7-day strip whose
    per-day counts match your actual completions.
  - Tiles: Done this week, On time this week, Best streak, and Days
    together counting from the adoption date. **If** the profile has no
    adoption date (very old account), a Coins tile shows instead.
  - Last 4 weeks bar chart with an "X% on time · busiest on <weekday>s"
    caption. Sanity-check the caption against your real week.
  - Your rhythm: morning/afternoon/evening/night bars that reflect when
    you actually complete things, with a caption naming the top band.
  - Where tasks got done: per-list bars, biggest first, more than five
    lists folds the rest into Other. A deleted list's completions show as
    "Former list".
  - **If** the engine has noticed patterns / mined memories
    **[needs history]**: "has noticed" and "Worth remembering" cards
    appear. Under about 3 weeks of use both are correctly absent.
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
- [ ] Version string at the bottom matches the build you are testing.

## 7. Notifications

Grant permission when asked. **If** you decline: the app must keep
working fully; notification-dependent items below simply will not fire,
and the Notifications settings screen should reflect the denied state.

- [ ] Task reminder arrives at due time. Its Complete action completes the
  task (coins land, next occurrence spawns if repeating) without opening
  the app. Snooze options reschedule it.
- [ ] Morning rundown arrives in the morning with a ranked summary.
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
  - **If** one-off tasks went overdue during the vacation: a triage sheet
    lists them with complete / reschedule / dismiss, per-row and bulk.
    Later defers the sheet.
  - **If** nothing went overdue (only recurring items): NO sheet.
  - Your streak survived the vacation, and the pet's mood does not
    punish you - the comfort buffer eases you back over the first day.
- [ ] Open-ended vacation: around day 14 a gentle check-in asks if you are
  still away. At 30 days it ends itself.

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
