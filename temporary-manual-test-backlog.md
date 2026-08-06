# Temporary manual test backlog

> **TEMPORARY DOC.** This is a working backlog built from manual-test-plan-result.md and bugs.md
> after the 2026-08-03 test run. Every item here gets discussed, decided, and folded back into
> bugs.md, manual-test-plan.md, and manual-test-plan-result.md. When every section is closed,
> delete this file. It is not one of the living root docs.

Work through it a section at a time ("let's begin section 1"). Sections are ordered so the
cheapest wins come first and the discussion-heavy items come before their dependent code fixes.

Legend per item: **Refs** point at the bug entry or test-plan section. **Status** is one of
`doc-only` (no code, just update docs and retest), `decision` (Aaron picks a direction),
`fix` (direction agreed or obvious, code change needed), `infra` (server or tooling work).

---

## Section 1 · Doc-only closures and retests (no code) - **CLOSED 2026-08-04**

Facts verified in code; these just need the docs corrected and, where noted, a retest.

**Outcome.** All ten folded into manual-test-plan.md and the 8/4 run of
manual-test-plan-result.md (102 checked, 6 failed, 13 blocked, down from 7 and 18).
Two items turned into code work instead of doc fixes: **1.4 → BUG-015** (add the 11p
gridline) and **1.6 → BUG-014** (triage snackbar), both carried below as 5.4 and 3.5.
BUG-012 closed as answered-and-retested. Nothing else here needs a decision.

> **Dev tools path (used by several retests below):** DEBUG build only. You tab, scroll to the
> bottom, tap the "Scheduler inspector" row (subtitle "DEBUG · forecast vs pending queue"),
> then scroll to the **Test fixtures** card. Its "How to use" button opens the full in-app
> walkthrough; the steps below are the condensed pass. Fixtures write real Firestore
> completions (Stats, Best Hours, Done, and Journal will see them), so use a test account and
> tap **Delete fixtures** when the pass is over. Seeding twice without deleting is blocked.

- **1.1 Emoji-only pet names are by design.** Refs: plan §1 blocked, note on BUG-001. Status: doc-only.
  PetNameSanitizer explicitly allows any printable characters ("it's their pet"), strips controls/bidi, caps at 16 graphemes, falls back to "Mochi" when empty. Mark the plan item passing with a note.
- **1.2 Re-time badge is testable today, and its rules are already specced.** Refs: plan §3 blocked, BUG-012. Status: doc-only + retest.
  Rules: recurring + timed task, 8+ timed completions on 5+ dates, habitual finish 3+ hours from due time. UI: clock-arrow badge on Tasks and list-detail rows, suggestion chip in the editor. Close BUG-012 as answered, retest with the fixture.
  **Retest steps:**
  1. Dev tools path above, then tap **"Seed re-time fixture (9:00 series done at 19:00)"**. The status line confirms. This creates a daily recurring "[Seed] Daily review" whose eight past occurrences (due 9:00 AM) were completed around 7:00 PM, plus one live occurrence due tomorrow 9:00 AM.
  2. Go to the Tasks tab and find the "[Seed] Daily review" row (Upcoming). Expect a small circling-clock badge in the accent color on the row. It may also show in the list detail screen.
  3. Confirm the badge does NOT appear on Home, and never on an Apple Reminders row.
  4. Tap the row to open the editor. Expect the chip: "This usually gets done around 7:00 PM." with the reason line "Tap to change its due time from here on."
  5. Tap the chip: the due time fills with 7:00 PM and the chip flips to a quiet "7:00 PM set". Tap Save changes.
  6. Reopen or check the row: the occurrence now shows the 7:00 PM due time and the badge is gone. Complete it and confirm the NEXT occurrence also carries 7:00 PM.
  7. Optional negative check: dismiss the chip (small x) instead of accepting on a fresh seed; it stays gone unless a new proposal differs by an hour or more.
  8. Cleanup: **Delete fixtures**.
- **1.3 Suggested-time chip is testable today.** Refs: plan §4 blocked. Status: doc-only + retest.
  Rule: ~15 completions across 5+ dates within 42 days clustering in a ±90-minute window.
  **Retest steps:**
  1. Dev tools path above, then tap **"Seed new-time fixture (18 evening completions)"**. This creates a "Seeded fixtures" list holding 18 completed tasks, done around 7:00 PM across six past days.
  2. Create a new task (Home plus button or Tasks tab): any title, due date set to **TOMORROW**, leave the time unset, and pick the **Seeded fixtures** list. (Why tomorrow: a task due today within 30 minutes of the proposal is silenced by the lead-time guardrail, and 7:00 PM may already be past when you test.)
  3. Expect the suggestion chip near the time control: "{PetName} suggests 7:00 PM." with a reason line.
  4. Tap the chip to accept: the time fills with the proposal. Hand-editing the time afterwards must still work. Save.
  5. Open another new task on the same list and dismiss the chip (small x) instead. Reopen the editor: it stays gone; it only returns if a new proposal differs by an hour or more.
  6. Cross-check (optional): the dev screen's Suggestions inspector shows every gate passing for that scope (evidence, dates, peak share, runner-up).
  7. Negative checks (optional): with bedtime set so 7:00 PM falls inside it, the chip goes quiet entirely; a task due TODAY when it is already past 6:30 PM is silenced by the 30-minute lead guardrail.
  8. Heads-up: if your bedtime window covers 7:00 PM, the chip will never show; adjust bedtime first. Cleanup: **Delete fixtures**.
- **1.4 Day-by-day gridlines: fix the code, not the plan.** Refs: plan §6 FAIL. Status: **decided, became BUG-015 / item 5.4**.
  Code and in-app help said gridlines at 12p and 6p only; 11p was a bare label anchoring the late edge of the 5a-to-5a span. Decided 2026-08-04 to add the third gridline rather than document the asymmetry, because two lines leave a 7h / 6h / 11h split whose oversized evening band is exactly what the card is about. The plan already described three gridlines, so it needed no edit beyond a note. See 5.4.
- **1.5 Post-onboarding nudges already exist.** Refs: BUG-010. Status: doc-only (optional dev tooling in 6.3).
  NudgeCenter shows Home banners for notifications (incl. a denied/Open Settings variant), widget adoption, and Reminders import. Rate limits (no nudges in first 2 days, 5-day spacing, 14-day per-topic cooldown, retires after 2 dismissals) mean fresh QA accounts never see one. Close BUG-010 as already implemented.
- **1.6 Vacation "End now" test steps are now known.** Refs: plan §10 blocked. Status: doc-only + retest. **Retest PASSED 2026-08-04**, and surfaced BUG-014 / item 3.5 (no feedback after a triage choice).
  Exits: Home banner "End now", day-14 card "Welcome me back", or You > Vacation "Turn off & catch up". No seed data needed; the whole pass takes about ten minutes.
  **Retest steps, path A (end from Home):**
  1. Note your current streak count (You tab). Create a one-off task due TODAY with a time 2 to 3 minutes from now. Do not complete it.
  2. You > Vacation mode: keep the default end date (one week out) and turn it on. Home should now show the vacation banner ("On vacation · back {date}" with an End now button), a resting Mochi, "nudges paused" copy, and NO mood meter. Quick add and the task list remain visible (current design; changing that is decision 2.5).
  3. Wait until the task's due time has passed.
  4. Tap **End now** on the Home banner. Expect, immediately and in this order: banner disappears, then the triage sheet appears: Mochi at content, headline "Welcome back!", "Here's what came due while you were away", the task from step 1 listed with Complete / Reschedule / Dismiss, plus "Reschedule all to this week". Pick any action.
  5. After the sheet: mood meter is back, Mochi is awake at roughly content (a 24h grace, not instantly ecstatic or sad), and the streak count matches step 1 (vacation days never break the chain).
  6. Journal tab: a new moment "You and Mochi picked back up." dated today.
  **Path B (end from You):** repeat steps 1 to 3, then end via You > Vacation mode > **"Turn off & catch up"** (or the toggle). Nothing dramatic happens on the You screen; the triage sheet appears on your NEXT visit to Home. That deferral is by design.
  **Path C (nothing came due):** start and immediately end a vacation with no task coming due in between. No triage sheet appears. That silence is correct, not a bug.
  Note: the day-14 "Welcome me back" card and the 30-day auto-end cannot be reached manually; they are covered by unit tests (item 1.7).
- **1.7 Vacation 14-day check-in and 30-day cap: pass by unit test.** Refs: plan §10 blocked. Status: doc-only.
  VacationReentryTests + MoodForecastTests cover the cap ending an open-ended trip, check-in due at 15 days / not at 10 / never for fixed dates / snooze, plus Home-surface integration. Mark pass-by-test.
- **1.8 First-letter semantics: one-sentence rule.** Refs: plan §9 blocked. Status: doc-only (tests to add in 6.4).
  The first letter arrives on the Sunday of the week AFTER the adoption week, 7 PM. Sunday adopter waits 7 days, Monday 13, Wednesday 11. Wrinkle (deliberate): a Sunday adopter's completions after 7 PM adoption evening land in that first letter. Write the rule into the plan.
- **1.9 Push counting: answered.** Refs: plan §4, last item ("Push counting: move an incomplete task's due date to a later day"). Status: doc-only. **Closed, retest PASSED 2026-08-04**.
  It is the v2 procrastination signal from the requirements doc (`rescheduleCount`), landed early to accumulate evidence; today its one live consumer is the suggested-time engine, which weights a completion up to 3x when the task was repeatedly pushed. Snooze counts too; skip-occurrence and vacation triage deliberately do not. Nothing renders it, so it is a data check rather than a UI check, and the negative cases are pinned by TaskEditorViewModelTests. Written into the plan.
- **1.10 Backlog notes, no release action.** Refs: plan §3 Reminders note, §7 rundown in progress. Status: doc-only.
  Apple Reminders expansion ideas go to the post-v1 backlog. Morning rundown test was mid-flight; record its result when done.
  **Rundown verification steps (for the in-flight §7 test):**
  1. You > Notifications: Morning rundown toggle ON.
  2. Have at least two open tasks due today or overdue, then background the app.
  3. Same evening, open the dev Scheduler inspector (path above): the forecast / pending queue should show a rundown entry scheduled for tomorrow morning. If it is missing here, it will not arrive; note what the inspector shows.
  4. Next morning at the scheduled hour, expect exactly one rundown notification with a count-style summary (no task titles if the privacy toggle is on). Tapping it opens the app.
  5. Confirm it never arrives inside your bedtime window and that toggling the setting OFF removes the queued entry in the inspector.

## Section 2 · Product decisions - **CLOSED 2026-08-05**

Each needed a call from Aaron before any code moved.

**Outcome.** All seven decided and shipped in one pass. Five closed bugs
(BUG-006, BUG-007, BUG-011, plus the two doc-only plan blockers) and one
decision that deliberately produced no code (2.5's Home half). Build and the
full test suite are green; three plan items are marked RETEST rather than
passing, since they are new behavior nobody has driven by hand yet.
**Unblocked downstream: 4.4** (widget vacation quiet state) now has its
direction and can be implemented with the rest of section 4.

- **2.1 Missing display name after reinstall (Apple sign-in).** Refs: plan §1 note, BUG-006. Status: **CLOSED 2026-08-05, shipped.**
  Apple only shares the name on the first-ever authorization; `saveAccountLink` already persists it when it arrives, so the gap is only ever a fresh profile document (delete the account, sign in again). Decided: lightweight one-time sheet over a full onboarding-style screen, because the app behind it is already usable - this is a gap being filled, not a step being taken. Entering Home with an empty display name presents "What should {PetName} call you?" with Save and a real "Not now" ("Mochi friend" stays the fallback). New `DisplayNamePrompt` trio under Onboarding/, plus `DisplayNamePromptGate` (per-UID device-local skip flag, NudgeLedger's shape, cleared by account deletion). BUG-006 closed as Fixed.
- **2.2 Kill the Sound toggle?** Refs: plan §6 blocked note. Status: **CLOSED 2026-08-05, shipped.**
  The toggle was inert: it persisted soundEnabled and nothing read it; the project contains zero audio code. Decided: remove the toggle, keep the schema field so a future audio pass needs no migration. `saveSoundEnabled` stays on the repository protocol (uncalled, with a note saying why). Plan and result updated.
- **2.3 Morning rundown toggle lives in two places.** Refs: BUG-007. Status: **CLOSED 2026-08-05, shipped.**
  Decided: Notification settings owns it; the You care-card row is gone, and so is the `setMorningRundown` action on YouBehavior. The Notifications list row's subtitle already names the rundown. With 2.2 this leaves the care card as a single Bedtime row, which was the accepted trade (the alternative, folding Bedtime into Notification settings, was rejected as an extra tap). BUG-007 closed as Fixed.
- **2.4 "Rated 4+" is hardcoded in the You footer.** Refs: plan §6 blocked. Status: **CLOSED 2026-08-05, shipped.**
  Decided: drop it. Footer is now "Mochi {version} · Made with care", and the version was already automatic (CFBundleShortVersionString), so there is no per-release action and no release-checklist line to add.
- **2.5 Should vacation hide tasks? Widget and Home, decided together.** Refs: plan §8 FAIL, §10 FAIL. Status: **CLOSED 2026-08-05 (decision only, no code here).**
  Decided to split it, as recommended. **Widget goes fully quiet**: resting pet + back date, no task rows - that is item **4.4**, still to build. **Home is unchanged**: quick add and the task list stay visible. Vacation pauses mood, nudges and recurring roll-forward; it does not lock you out of your own app, and someone who deliberately opens Home to check something should find their list there. The collapsed-summary middle ground was considered and dropped as a new state to build and test for no real gain. So plan §10's Home FAIL is reclassified as by-design; only the widget half was a real defect.
- **2.6 Confirm before deleting a one-off task?** Refs: plan §4 blocked. Status: **CLOSED 2026-08-05, shipped.**
  Decided: a destructive confirmation, matching the shape of the dialog recurring tasks already get, rather than waiting on the MochiSnackbar undo from 3.5. `deleteTapped` now opens the plain confirm for everything the skip-vs-series dialog does not cover, which pulls in the dateless-recurring edge that used to delete on the first tap (its message says the series stops). Three unit tests added; the old `delete()` test was rewritten, since it asserted the very behavior we removed. Revisiting undo-instead-of-dialog stays open as future polish once MochiSnackbar has proven itself in the triage sheet.
- **2.7 Untimed "Today" tasks: surface the default reminder time.** Refs: BUG-011. Status: **CLOSED 2026-08-05, shipped.**
  Decided: name the real time, do not invent a due time the task does not have. The editor's Time block gains a subtitle, "Reminds at 9:00 AM", reading the user's actual `effectiveDefaultReminderMinutes` rather than a hardcoded 9:00, and it clears the moment a time is set. Cost was a `profileRepository` on TaskEditorViewModel (both routers updated), fetched alongside the existing lists and suggestions fetches; the note stays nil until it lands so it never flashes a wrong time. Task rows still read "Due later today" - unchanged, and deliberately out of scope. BUG-011 closed as Fixed.

## Section 3 · High-priority code fixes

Direction is clear; these are the release-risk items.

- **3.1 Sign-out / deletion leaves stale caches, and the widget keeps showing the old account.** Refs: BUG-002. Status: fix.
  Firestore disk cache is never cleared, in-memory repo caches drop only lazily on uid mismatch, App Group widget state is never cleared (widget keeps rendering the signed-out account's tasks and pet), and the onboarding "Not you? Switch account" path does even less teardown. Fix: clear App Group widget state + reload timelines and drop caching decorators eagerly on sign-out and deletion; consider Firestore clearPersistence on deletion; give the "Not you?" path the same teardown.
- **3.2 Home shows stale state after notification-action Complete/Snooze.** Refs: plan §7 FAIL. Status: fix.
  RootView's foreground pipeline has a 90-second cooldown, and notification actions do not count as drained work, so reopening within 90s skips the refresh. Fix: NotificationActionHandler sets a pending-action flag that bypasses the cooldown, same pattern as the widget completion queue.
- **3.3 Mood: soften the stress gate, remove the whiplash.** Refs: BUG-005, plan §4 Effort FAIL. Status: fix.
  One system, two symptoms. Effort works (Large ≈ +29 vs +14 unrated) but with stress ≥ 20 the gate zeroes all completion lift, which is why a Large completion "did nothing". And an instant +29 can cross the 80-point ecstatic boundary, causing sad-to-ecstatic-and-back. Fix: floor the gate (e.g., 0.3) so completions always help; ramp the displayed score over ~30-60s instead of stepping; stop firing the 1.3s happy-squish pose flip on completions (keep it for petting).
- **3.4 Guard against 24-hour rests.** Refs: BUG-004. Status: fix (root cause TBC with Aaron).
  Candidates: widget freezes lapsed/vacation into a 12h timeline and never re-evaluates (see 4.2), minimum vacation end (tomorrow midnight) started just after midnight, or a near-degenerate bedtime window (no minimum; 10:00 PM to 9:59 PM sleeps 23h59m). Fix regardless: enforce a max bedtime window (~14h) and make the widget re-evaluate vacation end per entry. Confirm with Aaron which surface showed the 24h rest.
- **3.5 Triage sheet confirms nothing after a choice.** Refs: BUG-014, plan §10, from retest 1.6. Status: fix.
  All three per-row actions in the "Welcome back" sheet are bare SF Symbol buttons with no labels, so the only feedback is the row vanishing. Reschedule is the worst case: `triageReschedule` spreads the pile across the next one to five days, so even a tester who knows a reschedule happened cannot tell where the task went. Dismiss is worse in kind - it permanently deletes with no confirm and no undo.
  **Requirements:**
  1. Build a reusable `MochiSnackbar` in CommonUI. There is no shared one today; the only precedent is a one-off `saveToast` inside LetterDetailView. 2.6 (one-off delete confirmation) and later flows want the same thing, so do not write a second one-off.
  2. Fire it on each per-row action, naming the task: "Completed {title}", "Rescheduled {title} to Thu", "Dismissed {title}". The reschedule string must name the day actually chosen, not "later this week".
  3. Give the Dismiss snackbar an **Undo**. It is the only irreversible action in the sheet and the one a mis-tap costs most.
  4. Bulk actions ("Complete all", "Reschedule all to this week", "Dismiss all") close the sheet, so they need a count form rather than a title: "Rescheduled 4 tasks". Dismiss all keeps Undo.
  5. Auto-dismiss on a normal toast timer, stack rather than overwrite when two fire in quick succession, and stay clear of the sheet's bottom buttons.
  6. VoiceOver announces the snackbar, and Undo is reachable before it auto-dismisses.
  **Use cases it fixes:** tapping the calendar icon, the row vanishing, and not knowing a reschedule happened at all (the 8/4 retest). And: dismissing a row looks identical to completing one, but silently destroys the task.

## Section 4 · Widget fixes

- **4.1 Onboarding widget previews misrepresent the real widgets.** Refs: plan §8 FAIL. Status: fix.
  Previews are hand-built mocks: square "medium" (real one is 2:1 side-by-side), "Beaming" is not widget vocabulary, the vitality meter and "2 left today" do not exist, interactive Complete rows are not shown, lock-screen families unmentioned. Fix: render previews from the real entry view with a mock entry so they cannot drift; mention lock screen.
- **4.2 Widget has no sleeping state at bedtime.** Refs: plan §8 FAIL. Status: fix.
  Bedtime is not in the shared App Group payload, so the widget shows an awake pet (with an active Pet button) while Home shows Mochi asleep. The data already exists at mirror time and is dropped. Fix: add bedtime to WidgetState, map in-window entries to the sleeping face, add timeline entries at window edges.
- **4.3 Widget pet button rarely changes the art.** Refs: plan §8 blocked. Status: doc-only (accept).
  Petting adds +8 and does reload the timeline, but art has four coarse buckets, so the face usually stays put; the text mood label moves more readily. Accept for v1, note in the plan. Optional future polish: a brief "petted" acknowledgment glyph.
- **4.4 Vacation widget quiet state.** Refs: plan §8 FAIL. Status: fix, **unblocked 2026-08-05 by decision 2.5**.
  Decided: the widget goes fully quiet - resting pet, "On vacation · back {date}", no task rows and no Complete buttons. Home is deliberately NOT changing to match; see 2.5 for why the two surfaces diverge.

## Section 5 · Animation and UI polish

- **5.1 Ecstatic hop crops Mochi's head.** Refs: BUG-003, plan §2 blocked. Status: fix.
  Canvas headroom is 24 units; hop (-22) stacks with breath bob (-9) and breath stretch (~-8.5), peaking ~15 units above the canvas (~11pt of head cut on Home). Fix: reduce hop peak to ~-12 AND add canvas headroom so the three animation tracks cannot collide with the edge.
- **5.2 Sleeping Z's bunch up.** Refs: BUG-008. Status: fix.
  All three Z's share one origin and size, smoothstep easing makes them dwell at path start/end, the stagger is uneven, and the last Z clips the canvas top. Fix: stagger origin and size per Z (the tired idle already does this), linearize travel, even out the stagger.
- **5.3 Context-menu task preview looks cramped.** Refs: BUG-009. Status: fix (root cause not yet dug).
  Give the preview an explicit ideal size so long titles/notes do not clip. Investigate when we reach this section.
- **5.4 Day by day: draw the missing 11p gridline.** Refs: BUG-015, plan §6, decided from 1.4. Status: fix.
  The card labels 12p / 6p / 11p on a 5a-to-5a axis but the gridline loop slices the tick array to its first two entries, so 11p is a bare label. Two lines split the span into 7h / 6h / 11h bands, and that oversized evening band is exactly the region Best hours is about; three give 7h / 6h / 5h / 6h.
  1. Drop the slice in StatsView's `allDaysBody` background so every axis tick draws its hairline.
  2. Update the help copy in BestHoursHelpView, which reads "The faint vertical lines mark noon and 6p".
  3. Check it in all five flavors and on an SE-class width - three hairlines behind seven stacked rows must still read as restraint, not graph paper. If it does not, the fallback is dropping the 11p label instead so labels and lines agree the other way.
  The test plan already described three gridlines, so no plan change beyond a note.
- **5.5 Vacation mode needs an explanation somewhere.** Refs: plan §10 note (8/3 and 8/4 runs). Status: decision then fix (small).
  Aaron's standing request: the Vacation screen turns on a mode with non-obvious consequences (mood pauses, nudges stop, recurring roll-forward stops, streak is protected, a triage sheet waits for you on return) and says none of it. Decide subtext under the toggle versus a small help screen like About these charts, then write it. Uncaptured until now; parked here so it does not get lost.

## Section 6 · Dev tooling and test coverage

Unblocks the remaining seed-data items and pins behaviors we could not manually reach.

- **6.1 Extend the dev seeder for multi-week history.** Refs: plan §5 "noticed" card, §6 Streaks & stats, §6 Best hours. Status: infra.
  The observation engine needs 3 distinct weeks plus 14-day stickiness; no current fixture spans that, and the seeder deliberately never touches streaks or coins. Add a multi-week done-history variant.
- **6.2 Debug controls for streak and anniversary banners.** Refs: plan §2 blocked ×2. Status: infra.
  Add a debug-only "set streak count" (and adoption-date override) so milestone and anniversary banners are testable; add a unit test that the streak banner beats the anniversary banner on a shared day.
- **6.3 Dev control to reset the nudge ledger.** Refs: follows 1.5. Status: infra (optional).
  Lets QA see the notification/widget/Reminders nudges without clock games.
- **6.4 Missing letter tests.** Refs: follows 1.8. Status: infra.
  Add unit tests for Sunday adoption eligibility and the adoption-Sunday-evening tail landing in the first letter.
- **6.5 Keyboard blocks the pet-naming view on back-navigation.** Refs: BUG-001. Status: fix.
  Dismiss the keyboard when navigating away from the naming step and keep the field visible above the keyboard when refocused. (Lives here so onboarding polish ships with a retest of §1 as a unit.)

## Section 7 · Server-side

- **7.1 Delete the RevenueCat customer on account deletion.** Refs: plan §12 blocked. Status: infra + decision.
  Requires a Firebase Cloud Function calling RevenueCat's delete-customer REST API (secret key cannot ship in the app). Decide: build now (Firebase repo tooling already exists) or ship v1 with a release-checklist known-gap line. Recommendation: build now.
