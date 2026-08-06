# MochiBuddy bug log

Bugs found while walking manual-test-plan.md. This file is written and read
back by tools/bug-log.html, so keep the shape of each entry. Editing the
fields by hand is fine.

Open: 11 | Fixed: 5 | Won't fix: 0 | Updated 2026-08-05

## BUG-016 When selecting subscription, if you select annual option then there is a weird clipping happening on the left of the annual option. Same with monthly but on the right side of the monthly option

- Status: Open
- Severity: Polish
- Area: Somewhere else
- Found: 2026-08-05

**Steps**

1. Start onboarding
2. Navigate to the view where you select your subscription
3. Select annual
4. Notice it gets clipped on the left on the annual view

**Notes:** Can upload screenshot if needed

## BUG-015 Day by day chart labels 12p, 6p and 11p but only draws gridlines at 12p and 6p

- Status: Open
- Severity: Polish
- Area: 6. You tab and settings
- Found: 2026-08-04

**Expected:** Three axis labels, three hairlines. Every label gets a line, so there is no rule to explain in the help copy.

**Actual:** Only 12p and 6p are drawn (StatsView.swift, the gridline loop slices the tick array to its first two entries). 11p is a bare label.

**Notes:** Decided 2026-08-04: add the third gridline rather than document the asymmetry. Two lines split the 5a-to-5a span into 7h / 6h / 11h bands, and the oversized evening band is exactly the region Best hours is about; three lines give 7h / 6h / 5h / 6h. Also update the help copy in BestHoursHelpView, which currently reads "The faint vertical lines mark noon and 6p". Test plan section 6 already describes three gridlines, so no plan change is needed.

## BUG-014 Vacation triage sheet gives no feedback after Complete, Reschedule or Dismiss

- Status: Open
- Severity: Major
- Area: 10. Vacation mode
- Found: 2026-08-04

**Steps**

1. Go on vacation with a one-off task that falls due while you are away
2. End the vacation and let the "Welcome back" triage sheet appear
3. Tap the calendar icon on a task row

**Expected:** A snackbar confirming what happened and, for reschedule, which day it picked.

**Actual:** The row silently disappears. Nothing says the task was rescheduled, and nothing says where it went.

**Notes:** All three per-row actions are bare SF Symbol buttons with no labels, so the only feedback is the row vanishing. Reschedule is the worst case because the destination is not guessable: triageReschedule spreads tasks across the next one to five days. Dismiss is worse in a different way - it permanently deletes the task with no confirm and no undo. Proposed copy: "Completed X", "Rescheduled X to Thu", "Dismissed X" with an Undo action. There is no shared snackbar in the app yet (the only precedent is a one-off saveToast inside LetterDetailView), so this wants a small reusable MochiSnackbar in CommonUI - other flows will want the same thing. (Note 2026-08-05: the one-off delete confirmation this used to point at shipped as a plain destructive dialog instead, so the snackbar's first and only caller is still this sheet. Swapping that dialog for an undo snackbar is future polish, not a dependency.)

## BUG-013 Mochi suggests time bug

- Status: Open
- Severity: Major
- Area: 4. Task editor
- Found: 2026-08-04

**Steps**

1. After seeding the 18 completions
2. Add a new task
3. tap the suggested time
4. then tap the x button to the right of the selected time
5. tap add time
6. It shows the "set at time" banner again even though we previously removed it
7. The x button to the right of time doesnt work either when the time picker is shown

## BUG-012 What are the rules on suggesting a new time to a recurring task and how do we display the new suggested time to the user?

- Status: Fixed
- Severity: Major
- Area: Somewhere else
- Found: 2026-08-03

**Notes:** Do we flag add a flag to the task tab bar icon, then a flag to the upcoming segment, then a flag on the recurring task list item. That way the user taps tasks, upcoming, recurring item. Then we show a suggested to new? So in summary how do we know if we should suggest a new time for a recurring task, do we do anything to alert the user of this, and what would it look like for the user to make that change? -- Answered and retested 2026-08-04, closing as already built (not a defect). When: the task is recurring AND timed, has 8+ timed completions across 5+ distinct dates, and the habitual finish sits 3+ hours from the due time. Alert: a circling-clock badge in the accent color on the Tasks tab row and the list detail row, deliberately never on Home and never on an Apple Reminders row. Change: tapping the row opens the editor showing a chip ("This usually gets done around 7:00 PM." / "Tap to change its due time from here on."); accepting fills the time and carries it to future occurrences, dismissing keeps it gone until a proposal differs by an hour or more. Retested with the "Seed re-time fixture" dev fixture; test plan section 3 now carries the steps.

## BUG-011 If we are making a task and we select Date -> “Today” but dont specify a time can we still show the time instead of saying “no time” it makes me confused on what the default time is.

- Status: Fixed
- Severity: Major
- Area: Somewhere else
- Found: 2026-08-03
- Fixed: 2026-08-05

**Notes:** Decided 2026-08-05: say what will happen, do not invent a due time the task does not have. A dated-but-untimed task is stored date-only and its reminder fires at the user's default reminder time, so the editor's Time block now carries a subtitle, "Reminds at 9:00 AM", reading the real configured value (`NotificationPrefs.effectiveDefaultReminderMinutes`) rather than a hardcoded 9:00. It disappears the moment a time is set. This needed a `profileRepository` on TaskEditorViewModel, fetched alongside the existing lists and suggestions fetches; the note stays nil until that lands, so it never flashes a wrong time. Rows still read "Due later today" - unchanged, and out of scope here.

## BUG-010 Can we alert the user if they dont enable notifications and such?

- Status: Fixed
- Severity: Major
- Area: Somewhere else
- Found: 2026-08-03

**Notes:** Did we add an alert on app load that will occasionally ping the user to enable notifications, import widgets, or import apple reminders if they did enable this in onboarding? It shouldn’t be super prevalent but a reminder would be good.

## BUG-009 Ive noticed the haptic 3d touch feed back preview to show a tasks details is small and occasionally shows as if it needs more padding or isnt properly displaying the complete task details. Can this be improved?

- Status: Open
- Severity: Major
- Area: Somewhere else
- Found: 2026-08-03

## BUG-008 The sleeping "Z" when mochi is getting sleepy bunch up on each other. Could use some refinement

- Status: Open
- Severity: Polish
- Area: Somewhere else
- Found: 2026-08-03

## BUG-007 We show morning run down on the you view and in the notification settings. I think this only needs to live in the notification settings

- Status: Fixed
- Severity: Major
- Area: 6. You tab and settings
- Found: 2026-08-03
- Fixed: 2026-08-05

**Notes:** Both toggles wrote the same profile field (`notificationPrefs.morningRundown`) with different subtitles. Decided 2026-08-05, matching the original instinct: Notification settings owns it. The You care card row is removed; the Notifications list row's subtitle already names the rundown when it is on, so nothing is hidden. The inert Sound toggle came out of the same card in the same pass, which leaves the care card as a single Bedtime row (deliberate).

## BUG-006 You tab not showing name

- Status: Fixed
- Severity: Major
- Area: 6. You tab and settings
- Found: 2026-08-03
- Fixed: 2026-08-05

**Steps**

1. Create an account
2. Delete the account
3. sign in again with apple
4. no name will be shown in the profile

**Expected:** We want name and nothing generic

**Actual:** Shows some random placeholder that the user can change

**Notes:** Confirmed to be the Apple limitation: the name comes over on the very first authorization only, and `saveAccountLink` already persists it when it arrives. Delete the account and sign in again and Apple sends nothing, so the fresh profile document has no display name to show. Discussed 2026-08-05, decided: ask, do not invent. Entering Home with an empty display name now presents a sheet, "What should {PetName} call you?". Revised later the same day: the sheet is required - the original "Not now" exit was cut, interactive dismissal is disabled, and saving a name is the only way out. That closes the ask structurally (it only fires on an empty name), so the skip flag and DisplayNamePromptGate were removed with it. Chosen over a full onboarding-style screen because the app behind it is already usable - this is a gap being filled, not a step being taken.

## BUG-005 Mochi changes moods when i pet him or finish a task and it looks terrible to have him switch from his current mood to an estatic one. Perhaps this shouldnt update mochis mood?

- Status: Open
- Severity: Major
- Area: Somewhere else
- Found: 2026-08-03

**Notes:** Open to discussing this. However in its current state it looks terrible to have him go from sad to very happy back to sad.

## BUG-004 Some how I got mochi to rest for 24 hours. how does that happen?

- Status: Open
- Severity: Major
- Area: Somewhere else
- Found: 2026-08-03

## BUG-003 When mochi is estatic he hops too high and gets his top cropped out. I think he might need to hop a little less but im open to other ideas

- Status: Open
- Severity: Polish
- Area: 2. Home
- Found: 2026-08-02

## BUG-002 Is caching handled properly when we sign out or delete account? Im assuming it gets cleared?

- Status: Open
- Severity: Major
- Area: Somewhere else
- Found: 2026-08-02

## BUG-001 Keyboard blocks view when returning to add mochi name

- Status: Open
- Severity: Major
- Area: 1. Onboarding and sign-in
- Found: 2026-08-02

**Steps**

1. Add a name to mochi
2. with the keyboard present tap the "Let's Begin" button that appears above the keyboard
3. Now return back to the name mochi view
4. observe the keyboard is still showing and blocks the view

**Expected:** I would expect either the view to show the text box above the keyboard or that we would dismiss the keyboard regardless of avenue when we navigate to the next view

**Actual:** Keyboard blocks view and view is unable to dismiss keyboard so i cannot tap into the name textbox
