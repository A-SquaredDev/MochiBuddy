//
//  CachingTaskRepositoryTests.swift
//  MochiBuddyTests
//
//  The task cache's contract: reads cost at most one real fetch until a
//  refresh, every mutation is visible to the very next read (write-through,
//  no refetch), coverage math never serves a window it cannot prove, an
//  in-flight fetch can never clobber newer local state, and everything is
//  scoped to one uid. The observation-inputs memo rides the same hook.
//

import Foundation
import Testing
@testable import MochiBuddy

/// Holds an in-flight stub fetch until the test releases it.
@MainActor
private final class FetchGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

@Suite("CachingTaskRepository")
@MainActor
struct CachingTaskRepositoryTests {

    private func makeCache(
        incomplete: [TaskItem] = [],
        completed: [TaskItem] = []
    ) -> (CachingTaskRepository, StubTaskRepository) {
        let stub = StubTaskRepository()
        stub.incomplete = incomplete
        stub.completed = completed
        return (CachingTaskRepository(wrapping: stub, now: { Dates.now }), stub)
    }

    // MARK: - Read coalescing

    @Test("incomplete tasks cost one real fetch, then serve from memory")
    func incompleteCoalesces() async throws {
        let (cache, stub) = makeCache(incomplete: [makeTask(id: "a"), makeTask(id: "b")])
        for _ in 0..<5 {
            let tasks = try await cache.incompleteTasks(userId: "u")
            #expect(tasks.count == 2)
        }
        #expect(stub.incompleteFetches == 1)
    }

    @Test("a different uid is a cold cache - nothing leaks across accounts")
    func userSwitchDropsCache() async throws {
        let (cache, stub) = makeCache(incomplete: [makeTask(id: "a")])
        _ = try await cache.incompleteTasks(userId: "u1")
        _ = try await cache.incompleteTasks(userId: "u2")
        _ = try await cache.incompleteTasks(userId: "u2")
        #expect(stub.incompleteFetches == 2, "one real fetch per uid, not per call")
    }

    @Test("refresh re-warms the incomplete set eagerly")
    func refreshRewarms() async throws {
        let (cache, stub) = makeCache(incomplete: [makeTask(id: "a")])
        _ = try await cache.incompleteTasks(userId: "u")

        stub.incomplete = [makeTask(id: "a"), makeTask(id: "cross-device")]
        await cache.refresh(userId: "u")
        #expect(stub.incompleteFetches == 2)

        let tasks = try await cache.incompleteTasks(userId: "u")
        #expect(tasks.map(\.id).contains("cross-device"),
                "the foreground refresh is where cross-device edits land")
        #expect(stub.incompleteFetches == 2, "the post-refresh read is a cache hit")
    }

    // MARK: - Warm refresh reconcile

    @Test("a warm refresh keeps the stats anchor - the horizon never re-scans")
    func warmRefreshKeepsStatsAnchor() async throws {
        let (cache, stub) = makeCache()
        stub.completedStats = [
            makeStat(taskId: "s1", localDate: "2026-07-01"),
            makeStat(taskId: "s2", localDate: "2026-07-05"),
        ]
        stub.aggregationCount = 2
        let horizon = Dates.days(-132)
        _ = try await cache.completedTaskStats(since: horizon, userId: "u")
        #expect(stub.statsFetches == 1)

        await cache.refresh(userId: "u")
        #expect(stub.statsFetches == 2,
                "the reconcile delta is one bounded fetch above the newest cached row, not a horizon re-scan")

        _ = try await cache.completedTaskStats(since: horizon, userId: "u")
        #expect(stub.statsFetches == 2,
                "post-refresh stats reads stay cache hits - the old drop re-billed the whole horizon here")
    }

    @Test("a cross-device completion lands via the warm-refresh delta and pokes onMutation")
    func warmRefreshMergesDelta() async throws {
        let (cache, stub) = makeCache(
            completed: [makeTask(id: "c1", completed: true, completedAt: Dates.days(-1))]
        )
        stub.completedStats = [
            makeStat(taskId: "c1", localDate: "2026-07-07", completedAt: Dates.days(-1)),
        ]
        var mutations = 0
        cache.onMutation = { mutations += 1 }
        _ = try await cache.completedTasks(since: Dates.days(-7), userId: "u")
        _ = try await cache.completedTaskStats(since: Dates.days(-7), userId: "u")

        // Another device completes c2 while this one is backgrounded.
        stub.completed.append(makeTask(id: "c2", completed: true, completedAt: Dates.now))
        stub.completedStats.append(
            makeStat(taskId: "c2", localDate: "2026-07-08", completedAt: Dates.now)
        )

        await cache.refresh(userId: "u")

        let merged = try await cache.completedTasks(since: Dates.days(-7), userId: "u")
        #expect(merged.map(\.id) == ["c2", "c1"], "newest first, merged not refetched")
        let stats = try await cache.completedTaskStats(since: Dates.days(-7), userId: "u")
        #expect(Set(stats.map(\.taskId)) == ["c1", "c2"])
        #expect(stub.completedSinceFetches == 2, "seed + delta, no refill")
        #expect(stub.statsFetches == 2, "seed + delta, no refill")
        #expect(mutations == 1, "the observation memo must hear about the new history")
    }

    @Test("a cross-device removal fails the audit and drops to the refill path")
    func warmRefreshAuditCatchesRemoval() async throws {
        let (cache, stub) = makeCache(
            completed: [
                makeTask(id: "c2", completed: true, completedAt: Dates.days(-1)),
                makeTask(id: "c1", completed: true, completedAt: Dates.days(-2)),
            ]
        )
        stub.completedStats = [
            makeStat(taskId: "c1", localDate: "2026-07-06", completedAt: Dates.days(-2)),
            makeStat(taskId: "c2", localDate: "2026-07-07", completedAt: Dates.days(-1)),
        ]
        var mutations = 0
        cache.onMutation = { mutations += 1 }
        _ = try await cache.completedTasks(since: Dates.days(-7), userId: "u")
        _ = try await cache.completedTaskStats(since: Dates.days(-7), userId: "u")

        // c2 deleted on another device: invisible to a forward delta, so
        // only the count audit can notice.
        stub.completed.removeAll { $0.id == "c2" }
        stub.completedStats.removeAll { $0.taskId == "c2" }

        await cache.refresh(userId: "u")
        #expect(mutations == 1, "divergence must reach the observation memo")

        let after = try await cache.completedTasks(since: Dates.days(-7), userId: "u")
        #expect(after.map(\.id) == ["c1"])
        #expect(stub.completedSinceFetches == 3, "seed + delta + the refill the audit forced")
    }

    @Test("a warm refresh with no completion caches costs only the incomplete query")
    func warmRefreshSkipsUncachedCompletions() async throws {
        let (cache, stub) = makeCache(incomplete: [makeTask(id: "a")])
        _ = try await cache.incompleteTasks(userId: "u")

        await cache.refresh(userId: "u")

        #expect(stub.incompleteFetches == 2)
        #expect(stub.completedSinceFetches == 0)
        #expect(stub.statsFetches == 0)
    }

    @Test("a failed audit keeps serving the warm cache - offline fails soft")
    func offlineAuditFailsSoft() async throws {
        struct AuditOffline: Error {}
        let (cache, stub) = makeCache()
        stub.completedStats = [makeStat(taskId: "s1", localDate: "2026-07-05")]
        _ = try await cache.completedTaskStats(since: Dates.days(-7), userId: "u")

        stub.aggregationError = AuditOffline()
        await cache.refresh(userId: "u")

        _ = try await cache.completedTaskStats(since: Dates.days(-7), userId: "u")
        #expect(stub.statsFetches == 2,
                "seed + delta; an unreachable audit must not drop the cache")
    }

    // MARK: - Write-through

    @Test("completing a task moves it between caches with zero refetches")
    func completionMovesBetweenCaches() async throws {
        let (cache, stub) = makeCache(
            incomplete: [makeTask(id: "t1", listId: "chores", estimatedMinutes: 15)],
            completed: [makeTask(id: "old", completed: true, completedAt: Dates.days(-1))]
        )
        _ = try await cache.incompleteTasks(userId: "u")
        _ = try await cache.completedTasks(since: Dates.days(-7), userId: "u")

        try await cache.setCompleted(
            taskId: "t1", completed: true, localContext: nil, completedAt: Dates.now, userId: "u"
        )

        let incomplete = try await cache.incompleteTasks(userId: "u")
        let completedNow = try await cache.completedTasks(since: Dates.days(-7), userId: "u")
        #expect(incomplete.isEmpty)
        #expect(completedNow.first?.id == "t1", "newest first, moved not refetched")
        #expect(completedNow.first?.completed == true)
        #expect(completedNow.first?.completedAt == Dates.now)
        #expect(stub.incompleteFetches == 1)
        #expect(stub.completedSinceFetches == 1)
        #expect(stub.setCompletedCalls.map(\.taskId) == ["t1"], "the real write still went out")
    }

    @Test("un-completing moves the task back and drops its synthesized stat")
    func unCompleteMovesBack() async throws {
        let (cache, stub) = makeCache(incomplete: [makeTask(id: "t1")])
        _ = try await cache.incompleteTasks(userId: "u")
        _ = try await cache.completedTasks(since: Dates.days(-7), userId: "u")
        _ = try await cache.completedTaskStats(since: Dates.days(-7), userId: "u")

        try await cache.setCompleted(
            taskId: "t1", completed: true, localContext: nil, completedAt: Dates.now, userId: "u"
        )
        try await cache.setCompleted(
            taskId: "t1", completed: false, localContext: nil, completedAt: nil, userId: "u"
        )

        let incomplete = try await cache.incompleteTasks(userId: "u")
        let completed = try await cache.completedTasks(since: Dates.days(-7), userId: "u")
        let stats = try await cache.completedTaskStats(since: Dates.days(-7), userId: "u")
        #expect(incomplete.map(\.id) == ["t1"])
        #expect(incomplete.first?.completedAt == nil)
        #expect(completed.isEmpty)
        #expect(stats.isEmpty, "the undo removed the synthesized stat")
        #expect(stub.statsFetches == 1, "warm throughout - no refetch on either toggle")
    }

    @Test("a completion synthesizes the stat the server would have returned")
    func completionSynthesizesStat() async throws {
        let (cache, stub) = makeCache(incomplete: [
            makeTask(id: "t1", dueAt: Dates.hours(-2), hasTime: true, listId: "work", estimatedMinutes: 25),
        ])
        _ = try await cache.incompleteTasks(userId: "u")
        _ = try await cache.completedTaskStats(since: Dates.days(-132), userId: "u")

        try await cache.setCompleted(
            taskId: "t1", completed: true,
            localContext: CompletionLocalContext(
                localDate: "2026-07-08", localMinute: 620, timeZoneId: "America/Chicago"
            ),
            completedAt: Dates.now, userId: "u"
        )

        let stats = try await cache.completedTaskStats(since: Dates.days(-132), userId: "u")
        let stat = try #require(stats.first { $0.taskId == "t1" })
        #expect(stat.listId == "work")
        #expect(stat.estimatedMinutes == 25)
        #expect(stat.hasTime == true)
        #expect(stat.completedLocalMinute == 620)
        #expect(stat.completedLocalDate == "2026-07-08")
        #expect(stub.statsFetches == 1,
                "the hottest action in the app must never trigger a 132-day refetch")
    }

    @Test("add, update, snooze, roll, and delete all write through")
    func mutationsWriteThrough() async throws {
        let (cache, stub) = makeCache(incomplete: [makeTask(id: "keep")])
        _ = try await cache.incompleteTasks(userId: "u")

        var draft = TaskDraft(title: "New thing")
        draft.estimatedMinutes = 10
        let newId = try await cache.addTask(draft, id: "added", userId: "u")
        #expect(newId == "added")

        let edited = makeTask(id: "keep", title: "Renamed", dueAt: Dates.days(2))
        try await cache.updateTask(edited, countingReschedule: true, userId: "u")
        try await cache.snoozeTask(id: "added", to: Dates.days(3), userId: "u")
        try await cache.rollForwardTask(id: "added", to: Dates.days(4), missedOccurrences: 1, userId: "u")

        var tasks = try await cache.incompleteTasks(userId: "u")
        #expect(tasks.count == 2)
        let kept = try #require(tasks.first { $0.id == "keep" })
        #expect(kept.title == "Renamed")
        #expect(kept.rescheduleCount == 1, "a counting update increments locally too")
        let added = try #require(tasks.first { $0.id == "added" })
        #expect(added.dueAt == Dates.days(4))
        #expect(added.rescheduleCount == 1, "the snooze counted; the roll did not")

        try await cache.deleteTask(id: "added", userId: "u")
        tasks = try await cache.incompleteTasks(userId: "u")
        #expect(tasks.map(\.id) == ["keep"])

        #expect(stub.incompleteFetches == 1, "five mutations, zero refetches")
        #expect(stub.addedDrafts.count == 1)
        #expect(stub.updatedTasks.count == 1)
        #expect(stub.snoozeCalls.count == 1)
        #expect(stub.rollForwardCalls.count == 1)
        #expect(stub.deletedIds == ["added"])
    }

    @Test("every mutation fires onMutation - the observation memo's lifeline")
    func mutationsFireHook() async throws {
        let (cache, _) = makeCache(incomplete: [makeTask(id: "t1")])
        var fired = 0
        cache.onMutation = { fired += 1 }
        _ = try await cache.incompleteTasks(userId: "u")

        _ = try await cache.addTask(TaskDraft(title: "a"), id: "n1", userId: "u")
        try await cache.setCompleted(taskId: "t1", completed: true, localContext: nil, completedAt: nil, userId: "u")
        try await cache.setCompleted(taskId: "t1", completed: false, localContext: nil, completedAt: nil, userId: "u")
        try await cache.updateTask(makeTask(id: "n1"), countingReschedule: false, userId: "u")
        try await cache.snoozeTask(id: "n1", to: Dates.days(1), userId: "u")
        try await cache.rollForwardTask(id: "n1", to: Dates.days(2), missedOccurrences: 0, userId: "u")
        try await cache.deleteTask(id: "n1", userId: "u")
        #expect(fired == 7)
    }

    // MARK: - Coverage math

    @Test("a limit cache whose oldest row predates the window serves a since query")
    func sinceCoveredByLimitCache() async throws {
        let (cache, stub) = makeCache(completed: [
            makeTask(id: "new", completed: true, completedAt: Dates.days(-1)),
            makeTask(id: "old", completed: true, completedAt: Dates.days(-30)),
        ])
        _ = try await cache.completedTasks(limit: 50, userId: "u")

        let window = try await cache.completedTasks(since: Dates.days(-7), userId: "u")
        #expect(window.map(\.id) == ["new"])
        #expect(stub.completedSinceFetches == 0,
                "everything in the window is provably among the cached newest")
    }

    @Test("a full limit cache does NOT serve a window older than its oldest row")
    func sinceMissRefetches() async throws {
        let (cache, stub) = makeCache(completed: [
            makeTask(id: "a", completed: true, completedAt: Dates.days(-1)),
            makeTask(id: "b", completed: true, completedAt: Dates.days(-2)),
        ])
        _ = try await cache.completedTasks(limit: 2, userId: "u")

        _ = try await cache.completedTasks(since: Dates.days(-30), userId: "u")
        #expect(stub.completedSinceFetches == 1,
                "a full limit-2 cache can't prove there is nothing older - it must fetch")
    }

    @Test("a since cache with enough rows serves a limit query, and a bigger limit misses")
    func limitCoverage() async throws {
        let (cache, stub) = makeCache(completed: [
            makeTask(id: "a", completed: true, completedAt: Dates.days(-1)),
            makeTask(id: "b", completed: true, completedAt: Dates.days(-2)),
            makeTask(id: "c", completed: true, completedAt: Dates.days(-3)),
        ])
        _ = try await cache.completedTasks(since: Dates.days(-7), userId: "u")

        let two = try await cache.completedTasks(limit: 2, userId: "u")
        #expect(two.map(\.id) == ["a", "b"])
        #expect(stub.completedLimitFetches == 0,
                "rows outside the window are older than every row inside it")

        _ = try await cache.completedTasks(limit: 50, userId: "u")
        #expect(stub.completedLimitFetches == 1, "50 newest is more than the window proves")
    }

    @Test("stats windows serve from an anchor at or before them, and miss otherwise")
    func statsCoverage() async throws {
        let (cache, stub) = makeCache()
        stub.completedStats = [makeStat(localDate: "2026-07-07", completedAt: Dates.days(-1))]

        _ = try await cache.completedTaskStats(since: Dates.days(-132), userId: "u")
        _ = try await cache.completedTaskStats(since: Dates.days(-7), userId: "u")
        _ = try await cache.completedTaskStats(since: Dates.hours(-24), userId: "u")
        #expect(stub.statsFetches == 1, "the 132-day anchor covers every narrower window")

        _ = try await cache.completedTaskStats(since: Dates.days(-365), userId: "u")
        #expect(stub.statsFetches == 2, "a wider window than the anchor must fetch")
    }

    // MARK: - Guards

    @Test("an in-flight fetch never installs over a mutation that landed during it")
    func clobberGuard() async throws {
        let (cache, stub) = makeCache(incomplete: [makeTask(id: "t1")])

        // Park the first (cold) fetch mid-flight.
        let gate = FetchGate()
        stub.incompleteFetchDelay = { await gate.wait() }
        let inFlight = Task { try await cache.incompleteTasks(userId: "u") }
        while stub.incompleteFetches < 1 {
            await Task.yield()
        }

        // A mutation lands while the fetch is parked - the version bumps.
        stub.incompleteFetchDelay = nil
        _ = try await cache.addTask(TaskDraft(title: "mid-flight"), id: "mid", userId: "u")

        gate.open()
        _ = try await inFlight.value

        // The stale result must NOT have been installed: the next read
        // refetches instead of serving a snapshot that predates the write.
        _ = try await cache.incompleteTasks(userId: "u")
        #expect(stub.incompleteFetches == 2,
                "a version-stale fetch result is returned to its caller but never cached")
    }

    @Test("server barrier reads bypass the cache and refresh it with server truth")
    func barrierRefreshesCache() async throws {
        let (cache, stub) = makeCache(incomplete: [makeTask(id: "a")])
        _ = try await cache.incompleteTasks(userId: "u")

        stub.incomplete = [makeTask(id: "server-truth")]
        _ = try await cache.incompleteTasksFromServer(userId: "u")

        let tasks = try await cache.incompleteTasks(userId: "u")
        #expect(tasks.map(\.id) == ["server-truth"])
        #expect(stub.incompleteFetches == 2, "one default read, one server read, then cache")
    }

    @Test("task(id:) serves from warm caches and falls through when cold")
    func taskByIdUsesCaches() async throws {
        let (cache, stub) = makeCache(incomplete: [makeTask(id: "t1")])
        _ = try await cache.task(id: "t1", userId: "u")
        #expect(stub.taskByIdFetches == 1, "cold cache falls through")

        _ = try await cache.incompleteTasks(userId: "u")
        let hit = try await cache.task(id: "t1", userId: "u")
        #expect(hit?.id == "t1")
        #expect(stub.taskByIdFetches == 1, "warm cache answers without the doc get")
    }
}

@Suite("ObservationService · inputs memo")
@MainActor
struct ObservationInputsMemoTests {

    private func makeService() -> (ObservationService, StubTaskRepository, StubProfileRepository) {
        let taskRepo = StubTaskRepository()
        taskRepo.completedStats = [makeStat(localDate: "2026-07-07", completedAt: Dates.days(-1))]
        let profileRepo = StubProfileRepository()
        let service = ObservationService(
            authRepository: StubAuthRepository(),
            profileRepository: profileRepo,
            taskRepository: taskRepo,
            listRepository: StubListRepository(),
            ledger: ObservationLedger(defaults: UserDefaults(suiteName: "obs-memo-\(UUID())")!)
        )
        return (service, taskRepo, profileRepo)
    }

    @Test("the 132-day scan runs once per day, not once per surface")
    func memoServesRepeatCalls() async {
        let (service, taskRepo, profileRepo) = makeService()
        for _ in 0..<6 {
            _ = await service.engineInputs(now: Dates.now)
        }
        #expect(taskRepo.statsFetches == 1,
                "relay, Tasks refresh, Journal, Stats x2, editor - one scan serves them all")
        #expect(profileRepo.fetchCount == 6,
                "the profile half is NOT memoized - intervals must stay live (it reads the TTL cache)")
    }

    @Test("a task mutation invalidates the memo - stale history is unservable")
    func invalidationRefetches() async {
        let (service, taskRepo, _) = makeService()
        _ = await service.engineInputs(now: Dates.now)
        service.invalidateInputs()
        _ = await service.engineInputs(now: Dates.now)
        #expect(taskRepo.statsFetches == 2)
    }

    @Test("the memo is keyed by civil day - a new day refetches")
    func dayRollRefetches() async {
        let (service, taskRepo, _) = makeService()
        _ = await service.engineInputs(now: Dates.now)
        _ = await service.engineInputs(now: Dates.days(1))
        #expect(taskRepo.statsFetches == 2)
    }

    @Test("memoized inputs still carry the caller's now - time travel stays sound")
    func nowStaysLive() async {
        let (service, _, _) = makeService()
        _ = await service.engineInputs(now: Dates.now)
        let later = await service.engineInputs(now: Dates.hours(5))
        #expect(later?.now == Dates.hours(5),
                "the fetch is cached; the evaluation instant is always the caller's")
    }
}
