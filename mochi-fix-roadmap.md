# Mochi fix roadmap

Status: active. Sequenced from the August 2026 six-track investigation (anonymous accounts, journal, notifications, Firestore caching, animations, Done tab). Source docs: mochi-notifications.md, firestore-caching-investigation.md, done-tab-implementation-guide.md, Mochi-journal.md section 11.

Ordering rule: stop the bleeding first (steps 1 and 2), then correctness bugs, then performance, then the medium projects, then backend cleanup. Each step is shippable on its own branch and none blocks the ones after it unless noted.

## Phase 1: stop the bleeding

### Step 1: Isolate the test suite from production Firebase

Status: DONE 2026-08-01. Gate landed in MochiBuddyApp.swift: FirebaseApp.configure() still runs under XCTest (RemoteTuningTests reads the never-fetched default RemoteConfig instance, which traps without the default app), but RevenueCatConfig.configure() and the AppContainer boot are skipped, so splash never runs and no anonymous user or users/{uid} doc is created. Verified: full suite 770 passed, 0 failed, 1 skipped. Emulator wiring remains a future hardening option.

Why: every xcodebuild test run boots the real app via TEST_HOST, runs splash, and mints a live anonymous user plus a users/{uid} Firestore doc. This is the number one source of console clutter and it pollutes production data on every test run.

Integration method: environment gate at the composition root, not a build-setting change. In MochiBuddyApp, detect XCTest via ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] (the same signal RemoteTuning.bootstrap already uses) and short-circuit before FirebaseApp.configure() and AppContainer construction, rendering an inert placeholder view instead of RootView. This keeps TEST_HOST (the tests need the host app for @testable imports) while guaranteeing the app under test never touches the network. As a follow-up hardening layer, add Auth and Firestore emulator wiring behind a DEBUG launch argument so future integration tests have somewhere safe to point.

Files: MochiBuddyApp.swift, AppContainer.swift.
Verify: run the full suite on an erased simulator, confirm zero new users in the Firebase Auth console and zero new users/ docs.

### Step 2: Notification hygiene on sign-out and account deletion

Status: DONE 2026-08-01. clearForIdentityExit(userId:) added to NotificationRelaying and the orchestrator: cancels any queued relay, removes every pending id the app owns (foreign ids untouched, reusing NotificationPlanDiffer.isOurs), and wipes the exiting user's taper/shh/copy-deck state. Taper, shh, and copy-deck defaults keys are now scoped per uid, with legacy device-scoped values folded into the signed-in user's keys on first read. resetIdentity() added to MembershipStore (RevenueCat logOut, guarded for anonymous). Sign-out calls both after a successful signOut; deletion clears the queue after the data erase but before the auth delete (the erase already removed the tasks the promises referenced), and resets membership identity only on full success. Onboarding's "Not you?" switch was left alone: a pre-onboarding anon has no queue or taper history, and step 3 reroutes that exit anyway. Verified: full suite 774 passed, 0 failed, including four new tests.

Why: the pending notification queue survives identity changes, so an old account's task-titled promises and the repeating 7-day backstop keep firing forever. Taper, shh, and copy-deck state live in device-scoped UserDefaults and leak across accounts.

Integration method: a single teardown seam rather than scattered calls. Add a clearAllPending() method to the notification scheduling layer (UNNotificationScheduler behind its existing protocol) and a reset() on the orchestrator's persisted state (TaperTracker, shh valve, copy decks). Invoke both from the two identity exits: YouViewModel sign-out and DeleteConfirmViewModel deletion, alongside the existing ledger clears. Namespace the UserDefaults keys by uid so a future account switch cannot inherit the previous user's taper history. Also add the missing RevenueCat logOut() at sign-out for the same identity-boundary reason.

Files: NotificationOrchestrator.swift, UNNotificationScheduler.swift, TaperTracker.swift, YouViewModel.swift, DeleteConfirmViewModel.swift, RevenueCatMembershipStore.swift.
Verify: extend NotificationDeliveryTests with a sign-out-clears-queue case; manual pass with the DevScheduler screen.

## Phase 2: correctness bugs, small diffs

### Step 3: Auth hardening

Status: DONE 2026-08-01. isStaleSessionError narrowed to userNotFound and userDisabled (token expiry now keeps the cached session; pinned by a new classification test). ensureSession dedupes concurrent mints behind a shared in-flight Task. The credentialAlreadyInUse branch erases the anonymous placeholder's subtree (AccountEraser injected into FirebaseAuthRepository) and deletes its Auth user before signing into the existing account, best effort with the ops sweeper as backstop. AppSession gained flowEntry (.splash or .landing); every phase = .flow site sets it explicitly: sign-out and deletion land on Landing with no mint, Wake Mochi and the lapse gate still run splash. The wizard mints its session at navigateToMeetMochi (idempotent), so sign-in-only visitors never create a throwaway account; "Not you? Switch account" no longer mints either. Manual test plan gained three cases (Landing exits, console stays clean, collision deletes the orphan). Verified: full suite 775 passed, 0 failed. Leftover noted below in Phase 5: the splash "Try again" dead retry path (offline launch proceeds sessionless) predates this step and still exists; the wizard-entry mint shares that offline gap.

Why: three related defects mint or strand accounts. Token expiry is treated as user-deleted and silently swaps a real account for a fresh anon. ensureSession has no reentrancy guard, so overlapping calls can mint two accounts. The credentialAlreadyInUse path abandons the anon user and its Firestore doc forever (existing TEMPORARY-todo item 5).

Integration method: contain everything inside FirebaseAuthRepository so no caller changes. Narrow isStaleSessionError to userNotFound and userDisabled only; treat userTokenExpired and invalidUserToken as re-authenticate, never re-mint. Make minting idempotent by holding an in-flight Task handle (or converting the repository to an actor) so concurrent ensureSession calls share one signInAnonymously. In the credentialAlreadyInUse branch, capture the anon uid before linking, erase its data via the existing AccountEraser and delete the Auth user, then sign in with the existing credential; ordering matters because the client loses delete rights the moment the session switches. Finally, route sign-out and post-deletion exits to Landing instead of Splash so no replacement anon is minted until the user actually proceeds.

Files: AuthRepository.swift, OnboardingRouter.swift, YouRouter.swift, DeleteConfirmView.swift.
Verify: new tests in AccountLinkingTests (collision deletes the anon, double ensureSession yields one mint, sign-out is not followed by a mint); add an anonymousMintCount to StubAuthRepository.

### Step 4: Journal and letter bug fixes

Status: DONE 2026-08-01. Vacation-partial letters now pass the full maxBeats budget (fillOptionalBeats alone accounts for the structural beat), pinned by LetterComposerTests.vacationPartialFullBudget. The winning-compose bookkeeping records the observation conclusion only when the letter actually kept the observation beat, and a told list-return beat now records its qualified event under its real listId|firedOn key, carried via the new PeriodSummary.listReturnObservation field (defaulted, so test constructions were untouched). The Journal card consults momentumCoolingDown before surfacing: day-of it renders via the non-rotating peek, later cooldown days it rests, so lastSurfaced stops advancing daily and rundowns/letters get momentum back; supported by a new ObservationLedger.lastSurfacedDay helper with its own test. Mochi-journal.md sections 5 and 11 updated (fixed items moved to a history block; the surviving rough edge is the session-scoped phrasing cache, which now also affects momentum's day-of peek line). Verified: full suite 777 passed, 0 failed.

Why: four verified defects. Vacation letters cap at 2 beats instead of 3 (double subtraction in LetterComposer). A letter can mark an observation as surfaced without actually showing it, burning its dedup and cooldown. List-return beats used in letters are never recorded as surfaced (the mirror-image asymmetry). Daily Journal visitors permanently lock the momentum insight out of rundowns and letters because the card ignores the cooldown it sets.

Integration method: point fixes inside the composition layer, no schema or rules changes. Remove the redundant slot subtraction in LetterComposer. In LetterCompositionService, record surfaced conclusions and return events only when composed.beatTypes actually contains the corresponding beat. In JournalViewModel, consult momentumCoolingDown before surfacing the card so the card and the letter share one cadence. Everything stays deterministic, so existing letter snapshots in tests only change where the bug changed output.

Files: LetterComposer.swift, LetterCompositionService.swift, JournalViewModel.swift, ObservationLedger.swift.
Verify: JournalTests pinning the vacation beat count at 3 and the surfacing bookkeeping both ways.

### Step 5: Notification planner bug fixes

Status: DONE 2026-08-01. Rundown wake and the DEBUG inspector's quiet windows now anchor via calendar.date(bySettingHour:) so DST transition days keep their wall-clock promise, pinned by a fixed-zone America/Chicago spring-forward test. The backstop is decoupled from moodDips: planned whenever any notification pref is on, silenced only by a full opt-out (all four genres off), vacation, or lapse. NOTE the deliberate behavior change recorded in open question 3 below: moodDips defaults off, so default-pref users now get the 7-day dormancy backstop for the first time. Monthly promises on days 29-31 return nil repeating components and schedule their single next occurrence instead (nextOccurrence clamps correctly via byAdding month). UNNotificationScheduler catches center.add failures and logs a new scheduleFailed(id:) telemetry event; wired to OSLog telemetry in AppContainer. mochi-notifications.md updated (summary table, backstop section, bug list markers). Verified: full suite 780 passed, 0 failed.

Why: remaining verified defects from the notifications audit. Rundown fires an hour off on DST transition days. Disabling the moodDips preference silently kills the dormancy backstop. Monthly promises pinned to day 29 to 31 skip short months. Scheduling failures are swallowed by try? so telemetry counts plans, not deliveries.

Integration method: keep the planner pure and fix at the edges. Compute the rundown wake with calendar date components (hour and minute on the target day) instead of startOfDay plus elapsed seconds, in both NotificationPlanner and the DevScheduler mirror. Give the backstop its own gate independent of the moodDips preference. Clamp monthly promise day components with the calendar's shortest-month rule. Replace try? await center.add with a do/catch that records the failure in the existing telemetry path.

Files: NotificationPlanner.swift, PromiseTriggerBuilder.swift, UNNotificationScheduler.swift, DevSchedulerScreen.swift.
Verify: NotificationDeliveryTests with fixed-zone DST fixtures and a short-month promise case.

## Phase 3: performance

### Step 6: Animation quick wins

Why: no memory problem exists, but the idle canvases waste CPU and battery: about 360 Text layouts per second for the z glyphs, 120 Hz rendering behind sheets and on unselected tabs, a double full-canvas color-filter pass on unwell, and roughly 1,500 transient path allocations per second. Reduce Motion is ignored app-wide.

Integration method: additive parameters and hoisted constants, no visual redesign. Replace the per-frame Text("z") draws with a file-scope pre-traced Path, matching the existing mochiBodyPath pattern, and hoist the other geometrically constant paths and StrokeStyles the same way. Add a paused input to all five scripted idle canvases, driven by scenePhase, the three HomeView sheet bindings, and the TabCoordinator selection; pass it into TimelineView(.animation(paused:)). Cap cadence with minimumInterval at 1/60, and 1/30 for sleeping and unwell. Make the outer saturation modifier conditional and fold the unwell fever fade into fill colors instead of a root-context filter. Gate all idle canvases and the repeatForever set on accessibilityReduceMotion, falling back to the existing static canvasBody. Move the widget's ImageRenderer out of body into the TimelineProvider with one cached bitmap per mood.

Files: MochiScriptedIdle.swift, MochiPetView.swift, HomeView.swift, MainTabView.swift, MochiSkeleton.swift, MochiWidget.swift.
Verify: Instruments (Core Animation FPS and Allocations) before and after on the Home tab, with a sheet presented, and on a non-Home tab.

### Step 7: Firestore caching layer

Why: every read is a server-first one-shot, so the enabled disk persistence saves zero billed reads. The 132-day observation scan re-runs on nearly every user action. Three overlapping foreground pipelines refetch the world. Estimated 80 to 90 percent read reduction available.

Integration method: decorators over existing repository protocols, so view models and services keep their current interfaces; this mirrors the CachingUserProfileRepository pattern already in the codebase. Order inside the step, following the ranked plan in firestore-caching-investigation.md: first memoize ObservationEngine.Inputs per (userId, civil day) with invalidation on task mutations, since it kills the majority of doc reads; second, a write-through CachingTaskRepository that refreshes only on foreground; third, collapse to a single foreground pipeline in RootView and delete the scenePhase handlers in HomeView and TasksView; fourth, add a TTL to the profile cache's background refresh; fifth, the write-side batching (merge the two RewardsStore profile writes, WriteBatch the triage loops and widget drain); sixth, memoize the per-period letter check and drop the read-before-create probes.

Files: per the investigation doc; new decorator types live beside the repositories they wrap.
Verify: a debug read/write counter surface in DevScheduler or logs, comparing a scripted session before and after; existing store tests keep passing since protocols are unchanged.

### Step 8: Done tab pagination and makeover

Why: the 50-doc cap makes older history permanently unreachable, caps the weekly counter at 50, and starves per-list done sections. The screen also reads as one undifferentiated list.

Integration method: follow done-tab-implementation-guide.md as written. Cursor pagination on the existing completedAt ordering with a documentID tiebreak, 30-row pages, sentinel-driven infinite scroll with a Load older fallback button, an aggregation count query for the exact weekly number, month-boundary headers, a compact summary strip, and LazyVStack for the group list. Fits the existing MVVM shape with one new ViewAction (loadMoreDone) and two UIState fields; no new Router routes. The one new composite index (listId plus completedAt) fixes the ListDetail starvation in the same pass. Also trim the five-source refetch to the sources the visible segment needs.

Files and test plan: in the guide.
Depends on: nothing, but land after step 7 if both touch TaskRepository in the same window to avoid churn.

## Phase 4: backend and ops

### Step 9: Anonymous account backlog cleanup and sweeper

Why: the client can never delete orphaned anon users or their Firestore subtrees under current rules, so the existing backlog needs the Admin SDK, and steps 1 and 3 only prevent new orphans.

Integration method: two artifacts outside the app. First a one-shot Node Admin SDK script (run locally with a service account) that pages listUsers, filters providerData.length === 0 with lastRefreshTime older than 30 days, deletes the Auth user and recursively deletes users/{uid}. Run it once after steps 1 and 3 have shipped so it does not race active development. Second, the same logic as a scheduled Cloud Function (weekly) as a permanent safety net. Keep both in a new firebase/ops directory in the repo so they version with the rules.

Verify: dry-run mode printing the candidate list first; confirm your 3 real accounts and any active anon session are excluded by the provider and freshness filters.

## Open questions for Aaron (collect answers at the end of the fix run)

1. Cold-start deferred minting: should a true first launch also skip the splash mint and wait until the wizard starts, so browsing Landing creates nothing? (Post-sign-out entries already work this way after step 3.)
2. Offline first-run UX: the splash Try again path is dead and an offline launch proceeds sessionless, so wizard choices silently do not save. Fix as a visible retry screen, or queue writes locally until a session exists?
3. Backstop for default-pref users (behavior change shipped in step 5): mood dips default off, so before the fix most users had NO dormancy backstop; now everyone with at least one notification pref on gets the gentle 7-day-silence ping. Confirm this is the winback behavior you want, or choose a narrower gate (easy one-line revert).

## Phase 5: decisions, not yet scheduled

- Defer anonymous minting past Splash to the first real write, so a user who only views Landing never creates an account. Partially landed with step 3 (post-sign-out Landing entries mint only at wizard start); the remaining decision is whether COLD START should also defer past splash.
- Splash "Try again" dead retry path: failedToStart is never set true, so an offline launch silently proceeds with no session and onboarding writes no-op. Same gap applies to the wizard-entry mint added in step 3. Small fix, needs a decision on offline-first-run UX.
- Celebrations: decided 2026-08-01, will not become a notification genre. If celebrations are built at all they will be an in-app surface. The unused copy pool in NotificationCopy.swift can be removed when convenient.
- Anniversary backfill for marks that pass while the app is unopened (currently day-of only). Journal polish.
- One tasks snapshot listener replacing polling reads entirely: revisit after step 7 ships and real read numbers are known.
- Session-persistent observation phrasing cache (currently rotates on relaunch within a day). Cosmetic.

## Suggested branch sequence

1. fix/test-firebase-isolation (step 1)
2. fix/notification-identity-hygiene (step 2)
3. fix/auth-hardening (step 3)
4. fix/journal-letter-bugs (step 4)
5. fix/notification-planner-bugs (step 5)
6. perf/idle-animation-costs (step 6)
7. perf/firestore-caching (step 7)
8. feature/done-tab-pagination (step 8)
9. ops/anon-sweeper (step 9)

Steps 1 and 2 are independent and can be built in either order. Steps 4 and 5 are independent of everything else. Step 9 waits for 1 and 3.
