# Done Tab Implementation Guide · History pagination + screen makeover

> **Status: BUILT 2026-08-01** (roadmap step 8; full suite 818 passed, 0
> failed). As-built deltas from the plan: the Done fetch splits into an
> always-fetched today window (the Today segment and celebration math need
> it; served by the task cache) plus segment-gated history pages; the
> end-of-history footnote renders only when the timeline has content; the
> ListDetail scoped query falls back to the old global-page filter until
> the console composite index exists (tasks: listId ASC, completedAt DESC,
> still to create); the optional donePageSize Remote Config knob was NOT
> added (RC pin stays 84). Fold-then-archive into mochi-requirements.md
> still pending.

---

## 1. Scope in one paragraph

The Done segment of the Tasks tab (`MochiBuddy/Tasks/TasksView.swift`,
`TasksViewModel.swift`) shows completed tasks as a per-day timeline, but the
fetch is a hard cap of the **50 newest completions with no way to load older
history**. A long-time user's completions past row 50 are unreachable forever,
the "N done this week" subtitle silently tops out at 50, and ListDetail's done
section is starved by other lists' activity. This guide adds **cursor
pagination (infinite scroll)** to the Done timeline, an **exact week count via
an aggregation query**, **month boundary headers**, a **lazy render path**, and
a **scoped completed-tasks query for ListDetail**. No document migration, no
rules change, one new composite index (ListDetail only).

---

## 2. Current behavior (verified, not assumed)

Data lives in the flat per-user subcollection `users/{uid}/tasks`. Completed
tasks are ordinary task docs whose `completedAt` field exists; there is no
separate completions collection.

| What | Where | Behavior |
|---|---|---|
| Done fetch | `MochiBuddy/Tasks/TasksViewModel.swift:145` | `completedTasks(limit: 50, userId:)` on every refresh |
| Query | `MochiBuddy/Tasks/TaskRepository.swift:200-211` | one-shot `getDocuments()`, `completedAt > epoch` range + `order(by: completedAt, descending: true)` + `limit(to:)`. Range and order share a field, so no composite index is needed |
| Listener check | whole app | zero `addSnapshotListener` calls anywhere; every read is one-shot. No unbounded listeners exist |
| Refresh triggers | `MochiBuddy/Tasks/TasksView.swift:48-53` | `onAppear` plus every `scenePhase == .active` flip re-runs the full refresh (incomplete + completed + lists + profile + reminders), regardless of which segment is visible |
| Grouping | `MochiBuddy/Tasks/TasksViewModel.swift:394-424` | client-side bucketing into per-day groups, newest first; the cap is acknowledged in the doc comment at :391-393 ("the oldest day may be partial") |
| Render | `MochiBuddy/Tasks/TasksView.swift:189-200` + `MochiBuddy/CommonUI/DesignSystem/MochiTimeline.swift:22-35` | eager `VStack`/`ForEach` inside a `ScrollView`; nothing is lazy |

So the scare scenario (full-collection read, unbounded listener) **does not
exist**. The problem is the opposite one: the cap is doing its cost-control job
but it is a functional ceiling with no escape hatch.

### How many docs does a long-time user pull per screen load?

Exactly 50 completed docs plus all incomplete docs plus lists plus the profile
doc, on every Tasks-tab appearance and every foreground. Firestore offline
persistence softens repeat cost, but the Done fetch runs even when the user
never leaves the Today segment. Read volume is fine; visibility is not.

---

## 3. Decisions to lock

| # | Decision | Rationale |
|---|---|---|
| D1 | **Paginate with query cursors, page size 30, newest first.** First page replaces the current 50-cap fetch; older pages append on scroll. | Fits the existing single-field query exactly; each page is a bounded read; a light user never issues a second request. |
| D2 | **Cursor is (completedAt, documentID), not completedAt alone.** | `completedAt` is client-stamped and collisions are near-impossible but not impossible (widget drains). The two-field cursor is exact and costs nothing. |
| D3 | **"N done this week" comes from an aggregation count query, not the paged array.** | The current subtitle (`TasksViewModel.swift:319-322`) counts the capped 50-row fetch and lies for heavy users. `count()` over `completedAt >= weekStart` is exact and bills at most a handful of reads. |
| D4 | **No collapsible sections.** Month boundaries get a header row; older history is reachable by scrolling, gated by pagination. | The app deliberately has no expand/collapse component (settled during Best Hours, see `ProjectDocs/build-notes/best-hours-implementation-guide.md` §4). Pagination already limits what is on screen; collapse would solve a problem lazy loading has removed. |
| D5 | **Done segment renders in a `LazyVStack`; each day's `MochiTimeline` stays an eager `VStack`.** | Day groups are small (single-digit rows) so eager inside is fine; the outer list is what grows without bound once pagination lands. |
| D6 | **ListDetail gets a scoped query (`listId == X`, ordered by `completedAt`), capped at 20, no pagination.** | The current code (`ListDetail/ListDetailViewModel.swift:143-144`) filters the global newest-50 by list, so a busy user's list can show an empty done section despite recent completions. A scoped query fixes correctness; the full history lives on the Done tab, not per list. Requires the one new composite index (§7). |
| D7 | **The Done fetch runs only when the Done segment is selected (first page), and refresh keeps only the first page.** | Cuts the always-on 50-doc read for users who live in Today. On `selectSegment(.done)` fetch page one if empty; on `refresh` while Done is visible, re-fetch page one and drop the cursor so pull-in of stale appended pages cannot happen. |
| D8 | **Keep the existing visual language: `MochiTimelineDateHeader` day groups, dashed rail, `TodoItemRow`.** The makeover is structure (summary strip, month headers, load-more affordance), not a re-skin. | The timeline treatment is shared with Home and already approved. |

---

## 4. Firestore query changes

All in `MochiBuddy/Tasks/TaskRepository.swift`.

### 4a. Paged fetch

New protocol members (keep the existing `completedTasks(limit:userId:)` for
Home/tests until callers migrate, then fold it in):

```swift
struct CompletedPageCursor: Equatable {
    let completedAt: Date
    let documentID: String
}

struct CompletedTasksPage {
    let items: [TaskItem]
    /// nil when this page reached the end of history.
    let nextCursor: CompletedPageCursor?
}

func completedTasksPage(
    limit: Int, after cursor: CompletedPageCursor?, userId: String
) async throws -> CompletedTasksPage
```

Firestore implementation:

```swift
var query = tasks(userId)
    .whereField("completedAt", isGreaterThan: Timestamp(date: Date(timeIntervalSince1970: 0)))
    .order(by: "completedAt", descending: true)
    .order(by: FieldPath.documentID(), descending: true)
    .limit(to: limit)
if let cursor {
    query = query.start(after: [Timestamp(date: cursor.completedAt), cursor.documentID])
}
```

Notes:

- Range + first order stay on `completedAt`, satisfying the range-field-first
  rule; the `__name__` order is the implicit tiebreak made explicit so the
  cursor can include it. **No composite index is required** for this query;
  Firestore serves `field + __name__` orderings from the single-field index.
- `nextCursor` is built from the last returned doc; return nil when
  `documents.count < limit`.
- Keep the epoch lower bound (not `.distantPast`); year 1 is outside
  Timestamp's valid range (existing comment at `TaskRepository.swift:203-204`).

### 4b. Exact week count

```swift
func completedTaskCount(since: Date, userId: String) async throws -> Int
```

Implemented like the existing aggregations at `TaskRepository.swift:344-355`:
`whereField("completedAt", isGreaterThanOrEqualTo:)` + `.count` +
`getAggregation(source: .server)`. Fall back to the paged array's count if the
aggregation throws (offline), so the subtitle degrades to today's behavior
rather than showing zero.

### 4c. ListDetail scoped fetch (D6)

```swift
func completedTasks(listId: String?, limit: Int, userId: String) async throws -> [TaskItem]
```

`listId == nil` is the Inbox; Firestore cannot query field-absence, so for the
Inbox keep the current filter-the-global-page approach (Inbox starvation is the
same bug but there is no indexable predicate; accept and document). For a real
list: `whereField("listId", isEqualTo:)` + `completedAt` order + limit. This is
the one query that **needs a composite index** (§7).

---

## 5. View model changes

`MochiBuddy/Tasks/TasksViewModel.swift` and `TasksBehavior.swift`. All within
the existing ObservableStateViewModel / trigger / rebuild pattern; no new
architecture.

### UIState additions (`TasksBehavior.swift:57-85`)

```swift
/// Done only: an older page is available.
var canLoadMoreDone = false
/// Done only: the load-older request is in flight (drives the shimmer rows).
var isLoadingMoreDone = false
```

### ViewAction addition

```swift
case loadMoreDone
```

### Domain state

- `completed: [TaskItem]` keeps its role as the accumulated pages, newest
  first. Add `private var doneCursor: CompletedPageCursor?` and
  `private var doneWeekCount: Int?`.
- `refresh()` (`TasksViewModel.swift:141-167`): replace the line-145 fetch with
  the segment-gated first-page fetch (D7). Reset `doneCursor` on every
  first-page load. Fetch the aggregation count in the same pass.
- `loadMoreDone`: guard `!isLoadingMoreDone && doneCursor != nil`, fetch the
  next page, **append with de-dupe by id** (a task completed after page one
  loaded shifts the offsets; id de-dupe makes that harmless), advance the
  cursor, rebuild.
- `toggleTask` (`TasksViewModel.swift:186-229`) already inserts and removes
  from `completed` optimistically; that continues to work against the
  accumulated array unchanged.
- Subtitle (`TasksViewModel.swift:319-322`): use `doneWeekCount` when present;
  fall back to the current filter-count.
- `doneGroups` (`TasksViewModel.swift:394-424`): unchanged bucketing, plus
  month annotation: when consecutive day groups cross a month boundary, emit
  the month label so the view can render a divider header. Delete the
  "Earlier" undated branch (:398-401, :420-422); it is dead code, since the
  query guarantees `completedAt` exists (see §8 bug 5).

---

## 6. View restructuring

`MochiBuddy/Tasks/TasksView.swift`, Done branch only.

1. **Lazy list (D5).** Wrap `doneTimeline`'s group `ForEach`
   (`TasksView.swift:189-200`) in a `LazyVStack(spacing: 12)`. The rest of the
   screen (top bar, segTabs, celebration) stays in the eager `VStack`.
2. **Summary strip.** Under the celebration card, one compact `MochiCard` row
   with two facts: "This week · N" (exact, D3) and "Streak · N days" (already
   in UIState). Deliberately not the StatsView tile grid; the Done tab is a
   log, Streaks & stats is the analysis surface. Keep it to one row so the
   timeline stays the hero.
3. **Month headers.** Between day groups that cross a month boundary, render a
   `MochiTimelineDateHeader`-style row with the month name ("JULY 2026") using
   the existing uppercased/kerned muted treatment, so the scroll reads as a
   dated archive without a separate archive screen.
4. **Load-more affordance.** A sentinel view after the last group: when
   `canLoadMoreDone`, its `onAppear` triggers `.loadMoreDone` (infinite
   scroll), and while `isLoadingMoreDone` it shows two `SkeletonTodoRow`s with
   `.mochiShimmer()` (same bones as the loading skeleton at
   `TasksView.swift:103-128`). Also render a ghost `MochiButton` "Load older"
   as the explicit fallback for accessibility and scroll-restoration edge
   cases; both routes fire the same action.
5. **End state.** When the cursor is exhausted, replace the sentinel with the
   muted footnote treatment (`footnoteCard`, `TasksView.swift:222-230`):
   "That's the whole story since you adopted {petName}."
6. **No collapse controls** (D4). No monthly archive sub-screen; month headers
   plus lazy pages cover the archive need with zero new routes, which keeps
   `TasksRouter` untouched.

---

## 7. Index, rules, and migration needs

- **Document migration: none.** Pagination reads the existing docs and fields.
- **Rules change: none.** All queries stay inside `users/{uid}/tasks`.
- **Composite index: one, for D6 only** - collection `tasks`, fields
  `listId ASC, completedAt DESC`. Created in the Firebase console (this
  project manages Firestore config in the console, not a local
  `firestore.indexes.json`). Build order matters: ship the index before the
  ListDetail query change, or the query throws at runtime. The main Done
  pagination needs **no** new index.
- **Remote tuning (optional):** page size as a `RemoteTuning` key
  (`donePageSize`, default 30) next to the existing tunables, so the
  read-volume knob stays server-side.

---

## 8. Bugs found during the investigation

Fold fixes 1 to 3 into this build; 4 and 5 are cleanups.

1. **History ceiling.** `TasksViewModel.swift:145` caps the Done tab at the 50
   newest completions with no load-more path; everything older is permanently
   invisible. This is the core motivation for the guide.
2. **Week stat lies at 50.** `TasksViewModel.swift:319-322` counts "done this
   week" over the capped array, so the subtitle can never exceed 50. Same
   ceiling applies to the celebration math at :325-327 (needs 50 completions
   in a day to bite, so theoretical).
3. **ListDetail done-section starvation.** `ListDetail/ListDetailViewModel.swift:143-144`
   filters the global newest-50 by list; a busy user's other lists can push a
   list's own recent completions out of the window, showing an empty done
   section. Fixed by D6 (indexed scoped query) for real lists; Inbox remains
   best-effort (documented in §4c).
4. **Read amplification.** `TasksView.swift:48-53` re-runs the full refresh
   (five data sources including the 50-doc Done fetch) on every appearance and
   every foreground, regardless of segment. D7 gates the Done fetch by
   segment; the broader refresh cadence is acceptable and out of scope.
5. **Dead "Earlier" group.** `TasksViewModel.swift:398-401` and :420-422 handle
   completed tasks with nil `completedAt`, but the query
   (`TaskRepository.swift:206`) requires `completedAt > epoch`, so such rows
   can never arrive. Harmless; delete during the rebuild work.
6. **Not bugs, verified clean:** no snapshot listeners anywhere in the app
   (all reads are one-shot `getDocuments`); the unbounded
   `completedTasks(since:)` / `completedTaskStats(since:)` variants are always
   called with bounded windows (today, 24h, or at most the 3-month stats
   range); decoding 50 docs on the main queue is negligible at current sizes
   and stays negligible at page size 30.

---

## 9. Test plan

Fakes live in `MochiBuddyTests/TestSupport.swift` (`StubTaskRepository`, :400);
extend it with a paged stub backed by an array plus a recorded cursor, and a
settable aggregation count. Tests go in `MochiBuddyTests/TasksViewModelTests.swift`.

1. **First page renders.** Stub 30 completions across 3 days; select Done;
   assert 3 day groups newest first, `canLoadMoreDone` true when the stub
   reports a cursor.
2. **Load more appends without duplicates.** Two stub pages sharing one
   overlapping id; trigger `.loadMoreDone`; assert the union is de-duped and
   ordering holds.
3. **End of history.** Stub returns a short page with nil cursor; assert
   `canLoadMoreDone` flips false and a second `.loadMoreDone` performs no
   fetch (record call counts in the stub).
4. **Exact week subtitle.** Aggregation stub returns 87 with only 30 rows
   paged; assert the subtitle reads "87 done this week", and that an
   aggregation error falls back to the paged count.
5. **Toggle during paged state.** Complete a task with two pages loaded;
   assert it appears at the top of Today's group; uncomplete a row from an
   older page; assert it leaves the timeline and joins incomplete.
6. **Refresh resets pagination.** Load two pages, trigger `.refresh`; assert
   the array holds page one only and the cursor was reset (no stale-append).
7. **Segment gating.** With Today selected, assert refresh performs zero
   completed-page fetches; selecting Done performs exactly one.
8. **ListDetail scoping.** Scoped stub returns list-B completions; assert a
   list-A detail shows none and list-B shows its own, independent of global
   recency.
9. **Manual pass** (`manual-test-plan.md` addendum): airplane-mode load-more
   (shimmer resolves, no crash, footnote not shown falsely), VoiceOver on the
   "Load older" button and month headers, scroll position stability when a
   page appends.
