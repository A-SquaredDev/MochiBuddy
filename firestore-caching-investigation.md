# Firestore caching investigation

Date: 2026-08-01. Scope: every Firestore touchpoint in the app target, the read and write patterns behind them, what caching already exists, and a ranked plan to cut reads and writes. No code was changed for this investigation.

A note on billing mechanics that frames everything below: `PersistentCacheSettings` is enabled (MochiBuddyApp.swift:21-23), but a `getDocuments()` / `getDocument()` with the default source always goes to the server when online. The disk cache buys offline behavior and instant fire-and-forget writes; it does not reduce billed reads while online. Every "one-shot get" listed below is a billed server read per document returned, each time it runs.

## Current Usage Map

Collections in use, all under `users/{uid}`:

| Collection | Written by | Read by |
|---|---|---|
| `users/{uid}` (profile doc) | UserProfileRepository (all saves, coins, streak) | Nearly everything, via CachingUserProfileRepository |
| `tasks` | TaskRepository (add, update, snooze, roll, complete, delete) | Home, Tasks, ListDetail, ManageRepeating, orchestrator, ObservationService, letters, stats, Journal |
| `lists` | ListRepository (create, rename, color, delete, reorder batch) | Home, Tasks, ListDetail, editor, You, Stats, Journal, ObservationService, MomentWriter, letters |
| `moments` | MomentRepository.ensureMoment, adoption batch | JournalViewModel |
| `letters` | LetterRepository (transactional create, markRead) | Journal, LetterCompositionService, Home envelope |
| `activityWeeks` | LetterRepository.ensureActivityMarker | LetterCompositionService |

Non-Firestore stores for contrast: Remote Config (RemoteTuning, one activate plus one background fetch per launch), RevenueCat (MembershipStore, SDK-cached), App Group UserDefaults (widget state, comfort buffer, pending widget completions), UserDefaults (taper, shh, copy deck, ledgers). MembershipSession is a pure in-memory snapshot. The widget processes never touch Firestore at all.

### Read paths

All reads are one-shot gets. There is not a single `addSnapshotListener` in the codebase (verified by grep), so there are no realtime listeners to leak, and also no free cache-priming from listeners.

| Path | File:line | Pattern | Est. frequency per session |
|---|---|---|---|
| Profile fetch | UserProfileRepository.swift:70-75, wrapped by CachingUserProfileRepository.swift:28-50 | one-shot get; cache hit still spawns a background server get | 20 to 40 calls per session; roughly one server read each (see Existing Caching) |
| `incompleteTasks` | TaskRepository.swift:265-273 | one-shot query | Home refresh, Tasks refresh, ListDetail load, ManageRepeating load, orchestrator makeContext, VacationReentryService; 3+ per foreground, 1 per relay |
| `completedTasks(since:)` 24h/today | TaskRepository.swift:213-221 | one-shot query | Home refresh (today) and every relay makeContext (24h window) |
| `completedTasks(limit: 50)` | TaskRepository.swift:200-211 | one-shot query | Tasks refresh, ListDetail load |
| `completedTaskStats(since:)` short window | TaskRepository.swift:357-359 | one-shot query | Home refresh (24h), Journal load (trend window), Stats load (range window), letter engagement check |
| `completedTaskStats(since:)` 132-day scan | ObservationService.swift:127-129 (`replayDays 90 + windowDays 42`) | one-shot query over the full observation horizon; reads every completed doc in ~132 days | Every `engineInputs` call: every relay (via MemoriesService), every Tasks refresh (retime badges), Journal load, Stats load twice, editor open. Easily 10+ runs per session |
| `fetchLists` | ListRepository.swift:37-53 | one-shot query | Home, Tasks, Journal, Stats, editor open, ManageLists, You (count only), every engineInputs, letters, MomentWriter.listReturn |
| `moments` | MomentRepository.swift:86-92 | one-shot query, whole collection | Journal load |
| `letters` | LetterRepository.swift:54-67 | one-shot query, whole archive | Journal load, every foreground via composeIfDue existence check (LetterCompositionService.swift:219), markOpened, letter(id:) |
| `hasActivityMarker` | LetterRepository.swift:116-119 | one-shot doc get | once per period per foreground path, memoized in-session |
| `task(id:)` | TaskRepository.swift:314-319 | one-shot doc get | notification actions; widget drain, one per queued completion |
| Count aggregations | TaskRepository.swift:344-355 | server aggregation | onboarding surfaces only |
| Server-source barrier reads | TaskRepository.swift:361-380, UserProfileRepository.swift:77-82, LetterRepository.swift:58-59,121-124 | deliberate `.server` gets | letter composition only, about once per week; correct as designed |
| `ensureMoment` existence check | MomentRepository.swift:94-103 | doc get before create-only write | every moment attempt (milestones, list returns per relay, adoption repair) |
| Account erase traversal | AccountEraser.swift:27-44 | reads to delete | deletion flow only |

### Write paths

All ordinary writes are fire-and-forget merges (`completion: nil`), which is a good convention: the local cache applies instantly and the SDK syncs later. Nothing writes per keystroke; name and pref editors save on confirm only.

| Path | File:line | Pattern | Frequency |
|---|---|---|---|
| Task add/update/snooze/roll/delete | TaskRepository.swift:160-263 | 1 doc write per action | user-paced |
| `setCompleted` | TaskRepository.swift:275-299 | 1 doc write per toggle | per toggle |
| Coins increment | UserProfileRepository.swift:208-210 | 1 profile write per completion, per undo, per treat | per toggle |
| Streak save | UserProfileRepository.swift:212-226 | a second, separate profile write per completion | per toggle |
| Recurring spawn | TaskCompletionStore.swift:124 | 1 doc write per completed repeater | per repeat completion |
| Profile prefs saves | UserProfileRepository.swift:101-206 | 1 merge write per settings change | user-paced |
| List reorder | ListRepository.swift:77-83 | proper WriteBatch | good |
| Adoption stamp | UserProfileRepository.swift:164-175 | proper batch (profile + moment) | once |
| Letter create | LetterRepository.swift:72-95 | transaction | weekly |
| Triage loops | HomeViewModel.swift:212-260 | per-task writes inside for loops | on vacation re-entry |
| Widget drain | WidgetCompletionDrain.swift:70-86 | per-pending read + full completion pipeline in a loop | per foreground with queued taps |

Net cost of one live check-off: 1 task write + 1 coins write + 1 streak write, plus a spawn write for repeaters, i.e. 3 to 4 billed writes, then a debounced relay that performs 5 to 8 billed queries (below).

## Hot Spots

Ranked by estimated read volume.

1. The 132-day observation scan runs constantly. `ObservationService.engineInputs` (ObservationService.swift:119-139) fetches profile + every completed task doc in 132 days + lists. Its callers: MemoriesService.assignPersonalLayer (MemoriesService.swift:90-91) on EVERY notification relay; SuggestionService.retimeBadgeTaskIds (SuggestionService.swift:122) on every Tasks tab refresh; SuggestionService.beginSession (line 64) on every editor open; JournalViewModel.load (JournalViewModel.swift:233); StatsViewModel.load twice (StatsViewModel.swift:173 and :193). With a few hundred completions in the window, one session can re-read the same unchanged history thousands of document-reads over.

2. Every relay is a full re-read of the world. `NotificationOrchestrator.makeContext` (NotificationOrchestrator.swift:148-187) fetches profile, incompleteTasks, completedTasks(24h), plus `plannedLetterInput` (profile again, maybe marker, maybe a stats query, LetterCompositionService.swift:95-135), plus assignPersonalLayer (profile again + the 132-day scan + lists). Relays fire on every toggle (debounced 300ms), every foreground, every pet tap and treat (`.comfortChange`, HomeViewModel.swift:117 and :378), every editor dismissal. A single pet of the Mochi, which changes only a UserDefaults comfort buffer, currently costs a 132-day Firestore history scan.

3. Triple refresh on every foreground. Tabs stay mounted (MainTabView.swift:6-8), so three scenePhase handlers all fire on every activation: RootView.swift:99-127 (drain + letter foreground + relay), HomeView.swift:66-67 (full Home refresh: profile, incompleteTasks, completedToday, lists, 24h stats), TasksView.swift:51-52 (full Tasks refresh: incompleteTasks, completed 50, lists, profile, plus the 132-day retime scan). The same incompleteTasks query runs at least 3 times per foreground; lists at least 2 times; nothing shares results.

4. StatsViewModel fetches the observation inputs twice in one load. `noticedLines` (StatsViewModel.swift:173) and `minedFacts` (StatsViewModel.swift:193) each call `engineInputs`, doubling the most expensive query in the app within a single screen render, on top of the screen's own range-window stats fetch.

5. The profile cache does not actually suppress reads. CachingUserProfileRepository.swift:28-38 returns the cached profile but then always calls `refreshInBackground`, which performs a real server get (coalesced only while one is in flight). With 20 to 40 fetchProfile call sites firing per session, that is 20 to 40 profile doc reads per session for a document that this device almost always changed itself last.

6. Editor dismissal always refetches everything. Home and Tasks both run a full refresh on `.editorDismissed` (HomeViewModel.swift:162-165, TasksViewModel.swift:103-106) even when the editor was cancelled with no changes, then also request a relay, which re-reads the world again.

7. `letters` archive query on every foreground. composeIfDue's cache existence check (LetterCompositionService.swift:219) queries the whole archive each foreground; the result for the current period cannot change until the period rolls, so this is memoizable the same way `markerEnsuredForPeriod` already is.

8. Read-before-create on idempotent writes. `ensureMoment` (MomentRepository.swift:96) and `ensureActivityMarker` (LetterRepository.swift:108) pay a read to avoid a write that the security rules already reject harmlessly. A failed create costs nothing; the read costs a read every time.

## Bugs and Code Smells Found

No leaked or duplicate Firestore listeners exist because no listeners exist at all. The findings are of the redundant-read and write-in-loop variety:

- StatsViewModel.swift:173 and :193: duplicate `engineInputs` fetch (two full 132-day scans + two profile fetches + two lists fetches) in a single `load()`. The second call should reuse the first result.
- CachingUserProfileRepository.swift:40-50: background refresh on every cache hit means the "cache" converts reads from blocking to non-blocking without reducing them. Design gap rather than defect, but it defeats the store's stated purpose of read reduction.
- HomeView.swift:66-67 + TasksView.swift:51-52 + RootView.swift:99-127: three independent scenePhase(.active) pipelines, since all tabs stay mounted. Every foreground triggers three overlapping refreshes of the same data.
- HomeViewModel.swift:212-228 (triageComplete), :234-250 (triageReschedule), :252-260 (triageDismiss): per-document writes inside for loops. "Complete all" on an N-task pile issues roughly 4N sequential writes (task + spawn + coins + streak per item). Reschedule-all and dismiss-all are clean WriteBatch candidates.
- RewardsStore.swift:75-79: every completion issues two separate profile merge writes (incrementCoins then saveStreak) that could be one merge, saving one billed write per completion, the app's most frequent action.
- WidgetCompletionDrain.swift:70-86: one `task(id:)` doc read plus the full completion pipeline per queued tap, in a loop. Correct, but N queued taps cost N reads plus about 3N writes on the next open.
- MomentRepository.swift:96 and LetterRepository.swift:108: read-before-create against create-only rules (see Hot Spots 8).
- TasksViewModel.swift:145: `completedTasks(limit: 50)` refetches the same recent completions every tab selection and foreground; combined with Home's `completedTasks(since: startOfToday)` these are two shapes over the same underlying docs, fetched independently.
- Minor: StatsViewModel.statsCache (StatsViewModel.swift:29) never invalidates on new completions, so a completion made mid-visit does not appear when toggling ranges. Bounded by the screen's lifetime, worth a note in the invalidation design.

## Existing Caching

- Firestore offline persistence: enabled explicitly with `PersistentCacheSettings()` (MochiBuddyApp.swift:20-23), default size. This is what makes the app-wide fire-and-forget write convention safe, and serves reads offline. It does not reduce online billed reads (default-source gets always hit the server), and no code uses `source: .cache` reads outside the letter barrier's deliberate `.server` reads.
- CachingUserProfileRepository (CachingUserProfileRepository.swift): in-memory last-known profile with write-through mutation on every save method and a versioned background refresh. Correct coherence design; see above for its read behavior.
- StatsViewModel.statsCache (StatsViewModel.swift:29,105-110): per-range stats memo, scoped to one screen visit; makes range toggles free.
- SuggestionService.Session (SuggestionService.swift:22-29,62-80): observation inputs frozen per editor session so list changes mid-edit re-scope purely; explicitly designed as "no new query".
- MembershipSession (MembershipSession.swift): in-memory entitlement snapshot; RevenueCat's SDK caches customerInfo underneath.
- App Group (MochiShared/WidgetState.swift, WidgetStateMirror.swift, ComfortBufferStore): the widget renders entirely from the mirrored snapshot; widget taps queue into UserDefaults and drain later. The widget contributes zero Firestore traffic. This layer is healthy and needs no change.
- Session-scoped guards: TaskCompletionStore.completedTaskIds and spawn map (TaskCompletionStore.swift:44-51), LetterCompositionService.markerEnsuredForPeriod, JournalViewModel.surfacedLines.
- Instrumentation: FirestoreReadLog (App/FirestoreReadLog.swift) already logs every server read call site and cache hits, so before/after measurement of this plan is a `log stream` away.

## Recommendations (ranked)

Ranked by expected read/write reduction against implementation effort.

1. Memoize ObservationEngine.Inputs in ObservationService (high impact, low effort). ObservationService is already the single choke point for the 132-day scan. Cache the built `Inputs` keyed by (userId, civil day), invalidated by a completion-mutation hook and on sign-out. All six consumer paths (relay personal layer, retime badges, Journal, Stats, Memories, editor sessions) become one scan per day per mutation instead of one per surface visit. This alone removes the majority of document reads in a typical session. Also fixes hot spot 4 as a side effect if StatsViewModel still calls twice.
2. In-memory task store behind TaskRepository (highest impact, medium effort). A decorator (same pattern as CachingUserProfileRepository) that caches `incompleteTasks` and a recent-completions window, with write-through on every mutating method (all writes already funnel through the protocol). Home, Tasks, ListDetail, ManageRepeating, makeContext, and VacationReentryService all read from it. Invalidation: write-through for own writes, plus one real refresh per foreground for cross-device edits. Per-foreground incompleteTasks queries drop from 3+ to 1; per-toggle relay context becomes a pure in-memory read.
3. Single foreground pipeline (medium impact, low effort). Move the scenePhase(.active) work into one place (RootView already has most of it): drain, entitlement check, one shared data refresh, then let Home and Tasks re-derive from the shared stores of items 1 and 2. Deletes the triple refresh outright.
4. Stop the per-hit background profile refresh (medium impact, low effort). Give CachingUserProfileRepository a TTL or a refresh-on-foreground-only policy instead of refresh-on-every-hit. Profile reads drop from 20 to 40 per session to 1 or 2. Cross-device staleness window equals one foreground, same as today's practical behavior.
5. Merge the completion's profile writes and batch the loops (write-side, low effort). One merged coins+streak write in RewardsStore (saves 1 write per completion). WriteBatch for triageReschedule/triageDismiss and for the account-level parts of triageComplete. Batch the widget drain's task-document writes where possible. Note: batching mostly saves round trips and failure anomalies; billed writes are per document, so the real billing saver is the RewardsStore merge.
6. Skip refresh on cancelled editor dismissal (small, trivial). Have the editor report whether it saved; a no-op dismissal re-derives from cache and skips the relay.
7. Memoize the composeIfDue letters existence check per period (small, trivial), mirroring markerEnsuredForPeriod, and drop the read-before-create in ensureMoment (blind create-only setData; rules reject duplicates for free) or track ensured ids in memory.
8. Optional, larger: one snapshot listener on `tasks` (deferred). A single listener would replace most task queries and keep the cache warm, billing only deltas after the initial attach. Deferred because items 1 to 3 achieve most of the win without changing the app's one-shot mental model, and a listener interacts subtly with the letter barrier's server-read discipline.

Expected effect for a typical session (launch, two foregrounds, some tab switching, five check-offs, one Stats visit): document reads drop roughly 80 to 90 percent (the 132-day scan alone goes from 10+ runs to 1 or 2; profile reads from dozens to a couple; task-list queries from about 15 to about 4). Billed writes drop about 25 percent (one write saved per completion, plus batched triage), with round trips down further.

## Implementation Sketch

Phase 1 (pure wins, no behavior change):
- ObservationService: add `private var cachedInputs: (userId: String, day: String, inputs: Inputs)?`; `inputs(userId:now:calendar:)` returns it when userId and civil day match and no mutation has occurred since; expose `invalidate()`. AppContainer wires `taskCompletionStore.onMutation` (and task editor saves via the existing relay trigger point) to call it alongside the relay request. The lapse freeze already pins `effectiveNow`, so day-keying stays correct.
- StatsViewModel: fetch `engineInputs` once in `load()` and pass to both noticedLines and minedFacts.
- CachingUserProfileRepository: add `private var lastRefreshAt: Date?`; refreshInBackground guards on a TTL (for example 5 minutes) or is triggered only by the foreground pipeline.
- RewardsStore/UserProfileRepository: add `applyCompletion(coinsDelta:count:best:bestAchievedOn:lastActiveDate:userId:)` performing one merge; keep the old methods for their other callers.
- LetterCompositionService: `composedCheckedForPeriod` memo beside `markerEnsuredForPeriod`.
- MomentRepository.ensureMoment: drop the existence get, `setData` unconditionally, swallow the permission-denied duplicate.

Phase 2 (task store):
- New `CachingTaskRepository: TaskRepository` decorator created in AppContainer around FirestoreTaskRepository. State: `incomplete: [TaskItem]?`, `recentCompleted: [TaskItem]?` with a window anchor, version counter mirroring the profile cache's clobber guard. Reads serve cache when warm and log via FirestoreReadLog.recordCacheHit; mutations write through to Firestore fire-and-forget and update the arrays synchronously (setCompleted moves items between arrays; addTask appends; rollForward restamps). The `FromServer` barrier methods bypass and refresh the cache, exactly like fetchProfileFromServer does today.
- `refresh(userId:)` performs the two real queries; called only from the foreground pipeline and pull-to-refresh style entry points.
- View models keep their local arrays initially (smallest diff), just backed by cheap repository calls; a later cleanup can collapse them onto the store.

Phase 3 (foreground pipeline):
- RootView's scenePhase handler becomes the only foreground worker: drain, entitlement, `taskCache.refresh`, `profileCache.refresh`, letter foreground, one relay. HomeView and TasksView drop their scenePhase onChange and keep onAppear (tab re-selection) refreshes, which now hit warm caches.

Verification:
- FirestoreReadLog already labels every server read and cache hit. Capture a baseline session log before Phase 1 and the same script after each phase; the read counts per category are directly comparable. Unit tests: the caching decorators mirror CachingUserProfileRepository, which already has a test pattern in MochiBuddyTests for clobber-guard versioning to copy.

Invalidation rules summary:
- Task cache: write-through for all in-app mutations; full refresh on foreground and sign-in; drop on sign-out and account deletion.
- Observation inputs: invalidate on any completion-affecting mutation and on civil-day change; recompute lazily on next consumer.
- Profile cache: write-through (already); background refresh at most once per TTL or foreground.
- Letters/moments per-period and per-id memos: reset on period roll and sign-out.

---

# Round 2 audit: where the remaining ~500 reads per day come from

Date: 2026-08-01, after the round-1 plan landed (commit 3833d38 and follow-ups). IMPLEMENTATION STATUS 2026-08-01, same day: R1, R2, R3, R4, R5, and R6 below all landed - CachingListRepository, CachingLetterRepository (archive write-through + per-period marker memo), CachingMomentRepository, the warm-refresh delta reconcile with its count-aggregation audit in CachingTaskRepository, the 90-second foreground cool-down in RootView (a non-empty widget drain overrides it), and the meter now counting billed documents (`FirestoreReadLog.record(_:docs:)`, `NetworkCallMeter.count(_:by:)`, DevScheduler caption updated). R7 (the tasks snapshot listener) remains deferred. Watch the console for a few days; the DevScheduler meter is now directly comparable to it. Verified in code: the observation-inputs memo (ObservationService.swift:58-65, keyed by user + civil day, invalidated via CachingTaskRepository.onMutation wired in AppContainer.swift:173-175), the write-through CachingTaskRepository with coverage-aware completion windows, the profile TTL (CachingUserProfileRepository.swift:50-69, 5 min), the single foreground pipeline (RootView.swift:99-137 with tab pulses), applyCompletion's merged coins+streak write, composedCheckedForPeriod, and the blind-create ensureMoment. All seven round-1 recommendations are in. The console still shows ~500 reads per day. This section explains why and ranks what is left.

## Framing: the meter measures round trips, the console bills documents

NetworkCallMeter counts one per query (its stated design). Firestore's console counts one read per document returned. A single `completedTaskStats(since: 132 days ago)` call is 1 on the meter and N-completions-in-132-days on the bill. So a day that looks like "40 calls" on the meter is entirely consistent with 500 billed reads. Every estimate below is in billed documents. Recommendation R6 closes this instrumentation gap.

## The per-foreground residual bill

`CachingTaskRepository.refresh` (RootView.swift:129) drops every cached array and re-warms only `incomplete`. Everything else refills lazily, once, on its next consumer - per foreground. With tabs mounted, one activation costs roughly:

| What | Where | Billed docs (typical) |
|---|---|---|
| incompleteTasks warm-up | CachingTaskRepository.swift:58-65 | N incomplete (10-30) |
| completedTasks 24h/today refill | NotificationOrchestrator.swift:167 or HomeViewModel.swift:339 / TasksViewModel.swift:169 | last-24h completions, 1-2 queries (see anchor churn, F4) |
| completedTaskStats 24h refill | HomeViewModel.swift:342 | last-24h completions again |
| Letters archive, every foreground | LetterCompositionService.swift:89 → refreshUnread :474-477 | N letters (grows 1/week) |
| fetchLists, per surface | HomeViewModel.swift:340 + TasksViewModel.swift:178 (+ editor :94, Journal :238, Stats :112...) | N lists × 2-4 |
| Done page one + count, if Done segment visible | TasksViewModel.swift:457-463 | donePageSize (30) + 1 aggregation |
| Profile TTL background refresh | CachingUserProfileRepository.swift:57 | 1 |
| hasActivityMarker (cold launch only; in-memory period memo otherwise) | LetterCompositionService.swift:83-86 | 0-1 |

That is ~50-90 billed docs per activation for a modest account. Five or six activations a day is 300-450 on its own.

## The per-session history scan (F3, the growing term)

The interaction that survived round 1: `refresh()` drops the task cache's `stats` array but deliberately does NOT fire `onMutation`, so the observation memo (same civil day) stays valid - good. But the first check-off of the session runs `mutate` → `onMutation` → `invalidateInputs()`. The next relay (`.taskChange`, i.e. milliseconds later) rebuilds observation inputs, finds the task cache's `stats` still nil from the foreground drop, and pays the full 132-day server scan (ObservationService.swift:159-162 → TaskRepository.swift:466-505) plus a lists fetch. Subsequent completions in the same session are free (the synthesized-stat write-through keeps `stats` coherent and the memo rebuilds from a cache hit).

Net: one full 132-day completion scan per activation-that-contains-a-completion. At 90+42 days of horizon this term scales with total completion volume - at 3 completions/day it is ~400 docs per scan within a year of use, several scans a day. This is the number one residual cost and the only one that grows without bound (until the horizon saturates).

## Findings, ranked by billed-read volume

- F1. `fetchLists` is completely uncached. Twelve call sites (HomeViewModel.swift:340, TasksViewModel.swift:178, TaskEditorViewModel.swift:94 - every editor open, JournalViewModel.swift:238, StatsViewModel.swift:112, YouViewModel.swift:235, ManageListsViewModel.swift:143, MomentWriter.swift:108, ObservationService.swift:162, LetterCompositionService.swift:410 and :420, DeleteWarnViewModel.swift:67), each a billed query of the whole collection. Lists change rarely and every mutation already funnels through the ListRepository protocol - this is exactly the CachingUserProfileRepository shape, unbuilt.
- F2. Letters archive re-read every single foreground. `handleUserForeground` unconditionally calls `refreshUnread` (LetterCompositionService.swift:89), a whole-archive query, even though the unread flag only changes on compose (this device, weekly) and markRead (this device, or another device rarely). `composeIfDue` also reads the archive once per period before its memo sets (:230). The Journal reads the archive and the whole `moments` collection again on every tab visit (JournalViewModel.swift:120-121). None of letters/moments have a caching decorator; both are append-mostly.
- F3. The foreground drop + first-completion 132-day scan, described above. Also re-bills the 24h/today completion windows every activation.
- F4. Window-anchor churn on the shared `completed`/`stats` arrays. The cache keeps ONE coverage anchor (CachingTaskRepository.swift:99-113), so consumers that run narrow-first each pay a fresh server query over overlapping docs: orchestrator wants 24h (NotificationOrchestrator.swift:167), Home wants startOfToday (HomeViewModel.swift:339) and 24h stats (:342), Journal wants 28 days (JournalViewModel.swift:142, trendDays), Stats wants 7/28/90 (StatsViewModel.swift:108), observations want 132. Because the relay is debounced 300ms, the orchestrator-vs-Home ordering is racy; the same day's docs can be fetched 2-3 times under successively wider anchors before the widest lands.
- F5. No cool-down on the foreground pipeline. A 10-second detour to another app (share sheet, notification, app switcher) re-runs the entire pipeline: drop + warm-up + letters archive + lists + refills. Quick bounces bill the full ~50-90 docs each time.
- F6. Done tab: page one (30 docs) + the count aggregation re-fetch on every foreground while the Done segment is visible (TasksViewModel.swift:175-177), because the drop cleared page-one coverage.
- F7. Minor: cold-launch widget drain does `task(id:)` against a cold cache, one billed doc read per queued tap (WidgetCompletionDrain.swift; on warm foregrounds the previous session's arrays usually still cover it).
- F8. Instrumentation: the meter cannot see the number the console shows (round trips vs documents). Every diagnosis of "why 500" is currently guesswork by design.
- F9. Coherence note, not a cost: `refresh()` drops task arrays without invalidating the observation memo, so a cross-device completion delete can survive in observation inputs until midnight or the next local mutation. Accepted staleness, worth a comment.
- F10. Healthy paths confirmed: profile cache + TTL behaves as designed (~a dozen billed profile reads/day at heavy use), ensureProfile is 1 read per cold launch, aggregations bill 1 per 1000, the letter composition barrier's `.server` reads run weekly, the widget bills zero, and the meter/read-log choke points are correctly placed at every repository.

## Round 2 recommendations, ranked

- R1. CachingListRepository decorator (write-through, same pattern; drop on uid change; optional refresh on foreground). Kills ~10-15 queries × N lists per day for an afternoon's work. Highest value-per-effort.
- R2. Cache letters and moments. Letters: keep the archive in memory in a decorator (or in LetterCompositionService, which already owns the period memos); maintain `unreadLetter` by write-through on markRead/compose; hit the server once per period or per civil day instead of per foreground. Moments: append-only with every write already funneling through ensureMoment - cache the array, write through, refresh per day. Together this removes two whole-collection queries per foreground plus two per Journal visit.
- R3. Replace the foreground drop with a delta refresh. Keep `completed`/`stats`/their anchors across foregrounds; on refresh, fetch only `completedAt > newest-cached` (bills only genuinely new cross-device completions, normally zero) and merge. Guard divergence (cross-device delete/uncomplete) with one `completedTaskCount(since: anchor)` aggregation - 1 billed read - and full-refill only on mismatch. This eliminates BOTH the per-activation 24h refills and the per-session 132-day scan, the top residual and the only growing one. `incomplete` can keep the current full re-fetch (small and genuinely mutable) or adopt the same trick later.
- R4. Foreground cool-down: skip the whole pipeline if the app was backgrounded under ~60-120 seconds (drain still runs - it is local). Cheap insurance against app-switch bounces.
- R5. Done tab rides R3: with completion coverage preserved across foregrounds, page one becomes a cache hit again and the count aggregation can be gated on actual cache divergence.
- R6. Make the meter honest: pass `snapshot.documents.count` (or the aggregation's 1) into `FirestoreReadLog.record`/`NetworkCallMeter.count` so the daily number is billed documents and matches the console. Add a docs-per-category breakdown to the DevScheduler screen. Do this FIRST if landing incrementally - it turns every later item into a measured before/after.
- R7. Structural option, still deferred: one snapshot listener on `tasks` would replace the delta logic in R3 and bill only changed docs after attach, but it interacts with the letter barrier's server-read discipline and the one-shot mental model; revisit only if R1-R5 do not get the daily number where it needs to be.

Expected effect: R1+R2 remove roughly half of the per-foreground bill; R3 removes the history-scan term entirely (the largest single line and the one that grows with account age). A typical 6-activation, 8-completion day should land in the 60-120 billed-read range, dominated by the incomplete-tasks warm-up, and stop scaling with completion history.
