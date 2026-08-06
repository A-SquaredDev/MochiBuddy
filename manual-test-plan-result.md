# MochiBuddy manual test plan results

- Tester: Aaron McKain
- Build: (not recorded)
- Run finished: 8/4/2026, 11:43:29 PM
- Checked 102 of 102, 6 failed, 13 blocked

## 1. Onboarding and sign-in

- [x] Fresh install → launch. Onboarding flow appears (not the main app).
- [x] Sign in with Apple works. **But:** Apple only shares your name on the very first authorization ever; on a re-install the display name may be blank. That is expected - it is editable later in You.
  - note: Is there a way to detect no name was picked up? Can we show some extra screen or pop up or alert to get a name? Why would the user ever know if they delete, redownload, that they would need to manually change their name?
- [x] Sign in with Google works (browser sheet, returns to the app).
- [x] Meet Mochi naming step: you can name the pet or skip.
- [x] Name field: try a 30-character name - it caps at 16 visible characters. Try emoji-only and spaces-only - it never saves an empty or whitespace name.
  - note: Passes. Emojis allowed
- [x] Paywall shows real localized prices for monthly and annual. **But:** on a bad network it shows fallback prices ($3.99 / $29.99) - acceptable, retry on good network.
- [x] Sign out (You tab) and sign back in: you land in the app, not onboarding, with your data intact. The pet name and adoption date survive.
- [x] Sign out lands on the Landing screen (not the splash spinner), and no new anonymous user appears in the Firebase Auth console. Same after deleting an account. "Let's get started" from there still walks the wizard and saves choices normally.
- [x] Sign in with an already-used Apple/Google account from a fresh install: you land in your existing account, and the throwaway anonymous user that splash created is deleted from the Firebase Auth console (not left behind).
- [x] Delete the app, reinstall, sign in: everything returns from the server (tasks, name, streak, letters).
- [ ] **RETEST** **Nameless Apple account gets asked, once** (new 8/5, closes BUG-006). Delete the account in-app, sign in again with the same Apple ID, and expect the one-time "What should Mochi call you?" sheet on reaching Home. Check that "Not now" really does not come back.

## 1b. Done tab pagination

- [x] Tasks → Done: the timeline loads and scrolling near the bottom quietly loads older history (shimmer rows, then more days). The "Load older" button does the same with VoiceOver.
- [x] With more than 30 completions, "N done this week" shows the exact count, not a capped number. In airplane mode it falls back to counting the loaded rows and never shows zero wrongly.
- [x] Scrolling past a month boundary shows the "JULY 2026" divider.
- [x] Reaching the very end shows "That's the whole story since you adopted {pet}" and no spinner.
- [x] Airplane-mode load-more: the shimmer resolves without a crash and the end-of-history footnote is not shown falsely.
- [x] A list's detail screen shows that list's own recent completions even right after completing many tasks in other lists. (Requires the console composite index: tasks · listId ASC, completedAt DESC. Until it exists this falls back to the old behavior.)

## 2. Home

- [x] Greeting uses your display name; the mood line and pet references use the pet's name.
- [ ] **BLOCKED** The pet is drawn and animated. Tap the Pet button: a small happy reaction and the comfort meter bumps up. Repeated petting keeps bumping but the meter has a cap.
  - note: Mochi gets cropped BUG-003
      
- [x] Quick add: type a task and hit return. The field clears, the task appears in Today immediately.
- [x] Plus button opens the full editor prefilled for today.
- [x] Complete a task from Home: row moves to Done today, coins go up by 10, the coin pill updates. Undo the completion: the coins come back off.
- [x] Today shows all of today's tasks in a timeline; Done today and This week sections render below.
- [x] Mood reacts to your list: overdue tasks pull the mood down over time; completing things and petting push it up. **But:** mood never changes instantly to sad - it decays gradually.
- [x] **If** the current time is inside your bedtime window (You → Bedtime): the pet is asleep and stays asleep until the window ends.
- [ ] **BLOCKED** **If** you complete the task that lands a streak milestone (7, 30, then every 50): a celebration banner appears at that moment, and is dismissible. It does NOT appear for ordinary completions.
  - note: Is there a way to test this?
- [x] **If** an unread letter exists (Sundays onward, see section 9): a quiet envelope indicator shows on Home. Tapping it opens the letter inside the Journal tab.
- [ ] **BLOCKED** **If** today is an adoption anniversary (1 week, 1 month, then yearly): a banner on first open of the day. **But:** if a streak milestone lands the same day, the streak banner wins and the anniversary stays quiet (the weekly letter will still mention both).

## 3. Tasks tab

- [x] Four segments switch correctly; counts match reality.
- [x] Lists: tapping a list row pushes a list detail screen scoped to that list.
- [x] Done: a per-day timeline of completions. A coin banner sums the day; its X dismisses it for that day only (it returns tomorrow).
- [x] Completing and un-completing from this tab moves coins exactly like Home does. Streak and coins agree across Home, Tasks, and You.
- [x] **If** Apple Reminders lists are synced (You → Apple Reminders): imported rows appear alongside Mochi tasks. Completing one checks it off inside the Apple Reminders app too. **But:** Reminders completions earn no coins, and tapping a Reminders row never opens the Mochi editor.
  - note: This passes. But i think theres a lot of room for expansion on what we do with reminders
- [x] **Re-time badge [needs history]:** a recurring task with a time that you habitually finish hours away from its due time shows a small clock glyph with a circling arrow on its row, in the accent color. Tapping the row opens the editor with the re-time suggestion visible.

## 4. Task editor

- [x] New task: title field is focused with keyboard up. Editing an existing task: keyboard stays down until you tap a field.
- [x] Set date, time, priority, list, notes, repeat - all persist after save and survive an app restart.
- [x] Repeating task: complete it (anywhere - Home, Tasks, notification, widget). Exactly one next occurrence appears at the next due date. Never two.
- [ ] **RETEST** **Delete always asks first.**
  - note: Was BLOCKED 8/3 ("Should we show a confirmation when a user wants to delete a task?"). Answered 8/5: yes. One-offs now get a destructive confirm, and a repeating task with no due date is routed into it too instead of deleting on the first tap. Unit tests cover all three paths; retest by hand.
- [ ] **RETEST** **Dated but untimed task names its reminder time** (new 8/5, closes BUG-011).
- [ ] **BLOCKED** **Suggested time chip [needs history]:** with 3+ weeks of completions that cluster at a consistent time, opening a new task's time picker area shows a one-line suggestion chip with a reason.
  - note: UNSURE~ I think we need seed data to test this.
- [x] **Effort:** the Priority row carries a second control on the right under its own EFFORT label. Unset it reads "Set effort"; tapping opens a menu of Tiny, Small, Medium, Large, and Clear.
- [ ] **FAIL** **Effort and Mochi's mood [needs two accounts or two days]:** complete one Large task, versus three unrated tasks. The mood lift should look comparable. Coins must be identical either way (effort never changes coins). Rating something Tiny versus leaving it blank must have no effect at all.
  - note: Didnt see the mood go up at all when i finished a task with large effort. Should mochis mood have gone up?
- [x] Overdue behavior: a long task overdue does NOT stress Mochi more than a short one at the same priority. Effort only counts on the credit side.
- [x] Push counting: move an incomplete task's due date to a **later** day from the editor. Moving it earlier, or changing only the time, must not count as a push. (There is no user-visible surface for this yet; it is feeding a future feature, so this only matters if you are checking data.)
  - note: What feature will this feed into eventually?

## 5. Journal tab

- [x] Brand-new account: the Journal shows a single adoption moment ("The day your story began" or your named copy) - no empty charts, no placeholders.
- [x] With activity: a timeline grouped by month mixing letters and moments (adoption, streak milestones, anniversaries, returns).
- [x] **If** an unread letter exists: it is promoted to a hero card up top; tapping opens the detail. Once read, it returns to its place in the timeline and the unread styling clears.
- [ ] **BLOCKED** **If** the engine has noticed a pattern **[needs history]**: a card of one to three lines in the pet's voice ("Mornings are when things happen around here..."). Lines are qualitative - if you ever see a number or percentage in this card, file it.
  - note: UNSURE~ I think we need seed data to test this.
- [x] Footer: week strip with per-day counts, done-this-week count, best streak (hidden at zero), and a 4-week trend that only appears once you have two distinct weeks of history.

## 6. You tab and settings

- [x] Identity row: avatar letter, display name, email. Pencil edits the display name. Mochi+ badge shows when subscribed.
- [x] Flavor swatches: pick each of the five. The whole app re-themes immediately AND the home-screen app icon changes to match. **But:** on a slow device the icon change can lag a few seconds; it should self-correct by next launch at the latest.
- [x] Bedtime: change the window; Home's sleeping pose and notification quiet hours follow it.
- [x] The care card holds Bedtime and nothing else.
  - note: Was BLOCKED 8/3 ("What does sounds even do?"). Answered 8/5: nothing. The Sound toggle persisted `soundEnabled` and no code ever read it, so it is removed for v1 (schema field kept). The duplicate Morning rundown toggle is removed from the care card too; Notification settings owns it. Retest the care card, not the toggles.
- [x] Your Mochi card: shows name and "Met on <date>". Rename: the new name propagates immediately to Home greeting, mood lines, You header, notification action labels, the widget, and future notification copy. Rename works even while lapsed.
- [ ] **BLOCKED** **Streaks & stats** row opens the stats screen:
  - note: UNSURE~ I think we need seed data to test this.
- [ ] **BLOCKED** **Your best hours** card (the histogram):
  - note: UNSURE~ I think we need seed data to test this to see all the different possibilities
- [ ] **BLOCKED** **Day by day** card (seven weekday rows):
  - note: Looks like we are adding an action item to add the 11p mark
- [x] The "?" on both card headers opens **About these charts**. Its swatches should match the real card marks. Going back preserves your range and day selection.
- [x] Both cards, the day picker, and the help screen in **all five flavors**. Watch specifically for the IN WINDOW value and any tinted text on the inner card surface staying readable outside Black Sesame.
- [x] On a 320pt device (SE class) the tiles do not wrap and the legend stays on one line.
- [x] VoiceOver: the histogram reads its peak range and in-window share as one summary; each Day by day row reads its typical time or "still quiet"; the day pill announces "Day filter".
- [x] Notifications screen: per-category toggles (reminders, mood pings, rundown, weekly letter). Turning one off actually stops that category (verify over a day or two).
- [x] Apple Reminders: granting access lists your Reminders lists; chosen lists sync read-only into Tasks. Deny access: the screen degrades politely, no crash.
- [x] Manage lists: create, rename, recolor, delete. Deleting a list does not delete its completion history (see "Former list" above).
- [x] Manage subscription opens Apple's subscription page. Restore purchases spins, then reports found or not found honestly.
- [x] Footer reads "Mochi {version} · Made with care" and the version matches the build you are testing.
  - note: Was BLOCKED 8/3. Answered 8/5: the version is already automatic (CFBundleShortVersionString), so no per-release action is needed. The age rating was NOT automatic - "Rated 4+" was a hardcoded string that could never track App Store Connect - so it is removed from the footer.

## 7. Notifications

- [ ] **FAIL** Task reminder arrives at due time. Its Complete action completes the task (coins land, next occurrence spawns if repeating) without opening the app. Snooze options reschedule it.
  - note: reopening the app cause it to be stale. Had to reload the homeview to get the task to update to a 1 hour delay or show as completed. users might get confused if they open the app and dont see the task update
- [x] Morning rundown arrives in the morning with a ranked summary.
  - note: testing this right now
- [x] Mood pings: when tasks pile up overdue, a gentle ping in the pet's voice. Never more than 4 in a day, never inside bedtime or quiet hours.
- [x] Notification copy: pet name renders correctly everywhere, emoji only in celebration moments, and if you enabled the "hide task names" privacy toggle, task titles never appear on the lock screen.
- [x] Letter invitation (Sunday): one notification, tapping it lands directly on the letter inside Journal.

## 8. Widgets

- [ ] **FAIL** Long-press home screen → add Mochi widgets: small and medium exist, plus lock screen sizes.
  - note: The widgets shown in the onboarding view do not match the widget that exist for the user on the home screen. Can provide a screenshot if required
- [ ] **FAIL** The widget shows the pet and comfort/mood state consistent with the app.
  - note: Is there a sleeping state for the widget? In the app i see mochi is sleeping but it doesnt show in the widget. We need to investigate this issue
- [ ] **BLOCKED** Pet button on the widget bumps the comfort meter; the app agrees when opened.
  - note: Yes but I dont think the mochi asset updated to match the state. This might require further testing
- [x] Complete button on the widget checks a task off. **But:** coins land on next app open, not instantly on the widget - that is by design.
- [x] Rename the pet in the app: the widget picks the name up on its next refresh.
- [ ] **FAIL** **If** lapsed or on vacation: the widget switches to a matching quiet state instead of pretending everything is normal.
  - note: Should hide the tasks if on vacation. It currently shows that mochi is on vacation as well as the tasks and that seems incorrect to me.

## 9. Weekly letter [needs history - runs on real calendar weeks]

- [x] The first letter can only cover your first FULL Monday-to-Sunday week after adoption. Before that, no letter and no envelope - correct.
- [x] Sunday (from the send hour onward), open the app: a letter composes. Envelope on Home, hero in Journal, invitation notification (if that toggle is on).
- [x] The letter reads like the week you actually had (rough weeks get a gentler letter; quiet weeks a shorter one). It mentions a streak milestone or anniversary if the week had one.
- [x] Read it: unread indicators clear everywhere and stay cleared on other days.
- [x] Share: the share card defaults to the private variant; a full variant is offered per share. **If** it was a rough week: only the private card is offered. Save to Photos works (first time asks photo permission).
- [x] **If** the whole week was vacation, or you did nothing all week after week one: no letter for that week. Absence is correct.

## 10. Vacation mode

- [x] You → Vacation mode: date picker defaults one week out; open-ended is allowed.
  - note: This is fine but lets add subtext somewhere or maybe a help screen on this features view to explain Vacation mode and how it works.
- [ ] **FAIL** While on vacation: Home shows a vacation banner and a resting pet, mood UI is hidden, no mood pings or rundowns arrive (task reminders you explicitly set still do).
  - note: I believe this is a fail. I see mochi, mochi is resting, on vacation, a return date, and the remaining tasks. I feel like it should just say hes on vacation and then show mochi reseting.
- [x] End now (or the end date passing), then open the app:
- [x] Open-ended vacation: around day 14 a gentle check-in asks if you are still away. At 30 days it ends itself.

## 11. Membership states

- [x] Active subscriber: full app, Mochi+ badge in You.
- [x] **Lapsed** (subscription expired): the app degrades to a quiet checklist - tasks still work, but the pet sleeps, mood/celebrations pause, flavors lock, and You shows a Wake Mochi card. Account, legal, sign out, delete, and pet rename all still work. Only promise-type notifications continue. Journal shows the frozen record, and the Streaks & stats row is hidden while asleep.
- [x] Wake Mochi → resubscribe path works and everything resumes, including history recorded while lapsed.
- [x] **Billing grace** (payment failed but still entitled): app fully works plus a fix-payment nudge line in You.
- [x] Restore purchases on a fresh install with an active subscription entitles without repurchase.

## 12. Account deletion

- [x] You → Delete account: warning screen first; **if** a subscription is active, an extra screen explains deletion does not cancel the Apple subscription.
- [x] Deletion requires reauthentication, then erases data and lands you at onboarding.
- [x] Sign in again as a NEW account afterwards: nothing from the old account leaks in (no name, no streak, no letters, no "noticed" lines).
- [ ] **BLOCKED** Known gap: the RevenueCat customer record is not deleted (needs a server function). Do not file.
  - note: Whats required for this

## 13. Offline and multi-device

- [x] Airplane mode: browse, add, complete, rename - everything works against the local cache with no spinners hanging and no crashes. Back online: it all syncs up.
- [x] Force-quit immediately after completing a task, relaunch: the completion and coins survived.
- [x] **If** you run two devices on one account: tasks, coins, streak, letters, and the pet name converge on both. **But:** the comfort meter is per-device on purpose - do not file meter differences.

## 14. Cross-cutting polish passes

- [x] Dark and light appearance across every screen (Black Sesame is the dark theme).
- [x] Largest Dynamic Type size: Stats tiles, letter text, editor chip, and notification settings all wrap instead of truncating.
- [x] VoiceOver spot-check: Home pet controls, a task row, the week strip on Stats (each day announces its count), the rename field.
- [x] No copy anywhere uses em dashes; no UI emoji outside celebration notification moments; the pet name the user chose renders wherever "Mochi" would appear, while brand surfaces ("Mochi+") stay literal.
- [x] Rotate through a full day: no notification arrives inside bedtime, quiet hours drop pings rather than moving them to odd times.
