//
//  CachingCollectionRepositoriesTests.swift
//  MochiBuddyTests
//
//  The lists / letters / moments caching decorators share the profile
//  cache's contract: one real fetch per uid until the TTL, write-through
//  makes every in-app mutation visible to the very next read with zero
//  refetches, a background refresh past the TTL converges cross-device
//  edits, and a different uid is a cold cache.
//

import Foundation
import Testing
@testable import MochiBuddy

private func makeLetter(
    id: String = "letter-2026-06-29",
    periodStart: Date = Dates.days(-9),
    readAt: Date? = nil
) -> Letter {
    Letter(
        id: id,
        periodStart: periodStart, periodEndExclusive: periodStart.addingTimeInterval(6 * 86_400),
        timeZoneId: TimeZone.current.identifier,
        classification: .steady, beatTypes: [.smallTruePositive],
        lineIds: ["small-positive:0"],
        fullRenderedText: "A letter body.\n\nFrom Nori",
        privateRenderedText: "A letter body.\n\nFrom Nori",
        petNameSnapshot: "Nori", composedAt: periodStart.addingTimeInterval(6 * 86_400),
        composerVersion: 1, copyDeckVersion: 1,
        periodSummaryHash: "cafe", readAt: readAt
    )
}

private func makeMoment(id: String, occurredOn: String) -> Moment {
    Moment(
        id: id, type: .adoption, occurredOn: occurredOn,
        renderedTextSnapshot: "A moment", accessibilityTextSnapshot: "A moment",
        petNameSnapshot: nil, subjectNameSnapshot: nil,
        localeIdentifier: "en_US", copyDeckVersion: 1,
        sourceEventId: nil, createdAt: Dates.now
    )
}

// MARK: - Lists

@Suite("CachingListRepository")
@MainActor
struct CachingListRepositoryTests {

    @Test("lists cost one real fetch, then serve from memory")
    func fetchCoalesces() async throws {
        let stub = StubListRepository()
        stub.lists = [TaskList(id: "l1", name: "Chores", colorHex: "#C9A6FF", icon: "list.bullet", order: 0)]
        let cache = CachingListRepository(wrapping: stub)

        for _ in 0..<5 {
            let lists = try await cache.fetchLists(userId: "u")
            #expect(lists.count == 1)
        }
        #expect(stub.fetchCount == 1,
                "this query used to run as a billed server read from a dozen call sites")
    }

    @Test("every list mutation writes through - the next read needs no refetch")
    func writeThroughKeepsCacheCoherent() async throws {
        let stub = StubListRepository()
        stub.lists = [
            TaskList(id: "l1", name: "Chores", colorHex: "#C9A6FF", icon: "list.bullet", order: 0),
            TaskList(id: "l2", name: "Errands", colorHex: "#FFD9A6", icon: "cart", order: 1),
        ]
        let cache = CachingListRepository(wrapping: stub)
        _ = try await cache.fetchLists(userId: "u")

        // The stub's rename/delete/saveOrder are no-ops, so any change a
        // read observes can only have come from the cache's write-through.
        try await cache.renameList(id: "l1", name: "Housework", userId: "u")
        try await cache.saveOrder(ids: ["l2", "l1"], userId: "u")
        let created = try await cache.createList(
            name: "Garden", colorHex: "#A6FFD9", icon: "leaf", order: 2, userId: "u"
        )

        let lists = try await cache.fetchLists(userId: "u")
        #expect(lists.map(\.id) == ["l2", "l1", created.id], "saveOrder reordered, create appended")
        #expect(lists.first { $0.id == "l1" }?.name == "Housework")
        #expect(stub.fetchCount == 1)

        try await cache.deleteList(id: "l2", userId: "u")
        let afterDelete = try await cache.fetchLists(userId: "u")
        #expect(afterDelete.map(\.id) == ["l1", created.id])
        #expect(stub.fetchCount == 1)
    }

    @Test("past the TTL a hit refreshes in the background - cross-device edits converge")
    func backgroundRefreshConverges() async throws {
        let stub = StubListRepository()
        stub.lists = [TaskList(id: "l1", name: "Chores", colorHex: "#C9A6FF", icon: "list.bullet", order: 0)]
        let cache = CachingListRepository(wrapping: stub, refreshTTL: 0)

        _ = try await cache.fetchLists(userId: "u")
        stub.lists.append(TaskList(id: "cross", name: "New", colorHex: "#FFD9A6", icon: "cart", order: 1))
        _ = try await cache.fetchLists(userId: "u")
        await cache.refreshTask?.value

        let refreshed = try await cache.fetchLists(userId: "u")
        #expect(refreshed.map(\.id).contains("cross"))
    }

    @Test("a different uid is a cold cache")
    func userSwitchIsCold() async throws {
        let stub = StubListRepository()
        let cache = CachingListRepository(wrapping: stub)
        _ = try await cache.fetchLists(userId: "u1")
        _ = try await cache.fetchLists(userId: "u2")
        _ = try await cache.fetchLists(userId: "u2")
        #expect(stub.fetchCount == 2, "one real fetch per uid, not per call")
    }
}

// MARK: - Letters

@Suite("CachingLetterRepository")
@MainActor
struct CachingLetterRepositoryTests {

    @Test("the archive costs one real fetch, then serves from memory")
    func archiveCoalesces() async throws {
        let stub = StubLetterRepository()
        stub.stored = [makeLetter()]
        let cache = CachingLetterRepository(wrapping: stub)

        for _ in 0..<5 {
            let letters = try await cache.letters(userId: "u")
            #expect(letters.count == 1)
        }
        #expect(stub.archiveFetches == 1,
                "this whole-collection query used to run on EVERY foreground via refreshUnread")
    }

    @Test("markRead and a winning compose write through to the cached archive")
    func writeThroughKeepsArchiveCoherent() async throws {
        let stub = StubLetterRepository()
        stub.stored = [makeLetter(id: "older", periodStart: Dates.days(-16))]
        let cache = CachingLetterRepository(wrapping: stub)
        _ = try await cache.letters(userId: "u")

        let composed = makeLetter(id: "newer", periodStart: Dates.days(-9))
        _ = try await cache.createLetterIfAbsent(composed, userId: "u")
        try await cache.markRead(letterId: "older", at: Dates.now, userId: "u")

        let archive = try await cache.letters(userId: "u")
        #expect(archive.map(\.id) == ["newer", "older"], "newest first, inserted not refetched")
        #expect(archive.last?.readAt == Dates.now)
        #expect(stub.archiveFetches == 1)
    }

    @Test("the server barrier read refreshes the cache with server truth")
    func serverBarrierRefreshesCache() async throws {
        let stub = StubLetterRepository()
        stub.stored = [makeLetter(id: "composed-elsewhere")]
        let cache = CachingLetterRepository(wrapping: stub)

        let fromServer = try await cache.lettersFromServer(userId: "u")
        #expect(fromServer.count == 1)

        let cached = try await cache.letters(userId: "u")
        #expect(cached.map(\.id) == ["composed-elsewhere"])
        #expect(stub.archiveFetches == 0, "the barrier's answer warmed the cache for free")
    }

    @Test("a marked period answers hasActivityMarker from memory - markers are create-only facts")
    func markerMemoAnswersWithoutReads() async throws {
        let stub = StubLetterRepository()
        let cache = CachingLetterRepository(wrapping: stub)

        try await cache.ensureActivityMarker(periodId: "2026-06-29", userId: "u")
        let marked = try await cache.hasActivityMarker(periodId: "2026-06-29", userId: "u")
        #expect(marked)
        #expect(stub.markerChecks == 0, "ensure already proved the fact")

        // An unknown period delegates once; a confirmed true is then a fact.
        stub.markers.insert("2026-07-06")
        #expect(try await cache.hasActivityMarker(periodId: "2026-07-06", userId: "u"))
        #expect(try await cache.hasActivityMarker(periodId: "2026-07-06", userId: "u"))
        #expect(stub.markerChecks == 1)
    }

    @Test("a different uid drops the archive and the marker memo")
    func userSwitchIsCold() async throws {
        let stub = StubLetterRepository()
        let cache = CachingLetterRepository(wrapping: stub)
        try await cache.ensureActivityMarker(periodId: "2026-06-29", userId: "u1")

        stub.markers.remove("2026-06-29")
        let seen = try await cache.hasActivityMarker(periodId: "2026-06-29", userId: "u2")
        #expect(!seen, "u1's marker memo must not answer for u2")
        #expect(stub.markerChecks == 1)
    }
}

// MARK: - Moments

@Suite("CachingMomentRepository")
@MainActor
struct CachingMomentRepositoryTests {

    @Test("moments cost one real fetch, then serve from memory")
    func fetchCoalesces() async throws {
        let stub = StubMomentRepository()
        stub.stored = [makeMoment(id: "m1", occurredOn: "2026-06-01")]
        let cache = CachingMomentRepository(wrapping: stub)

        for _ in 0..<5 {
            let moments = try await cache.moments(userId: "u")
            #expect(moments.count == 1)
        }
        #expect(stub.fetchCount == 1,
                "this whole-collection query used to run on every Journal visit")
    }

    @Test("ensureMoment writes through newest-first and never dupes a natural key")
    func ensureWritesThrough() async throws {
        let stub = StubMomentRepository()
        stub.stored = [makeMoment(id: "m1", occurredOn: "2026-06-01")]
        let cache = CachingMomentRepository(wrapping: stub)
        _ = try await cache.moments(userId: "u")

        let newer = makeMoment(id: "m2", occurredOn: "2026-07-01")
        await cache.ensureMoment(newer, userId: "u")
        await cache.ensureMoment(newer, userId: "u")

        let moments = try await cache.moments(userId: "u")
        #expect(moments.map(\.id) == ["m2", "m1"], "newest first, inserted not refetched")
        #expect(stub.fetchCount == 1)
        #expect(stub.ensureLog == ["m2", "m2"], "the real create-only writes still went out")
    }

    @Test("past the TTL a hit refreshes in the background - cross-device moments converge")
    func backgroundRefreshConverges() async throws {
        let stub = StubMomentRepository()
        stub.stored = [makeMoment(id: "m1", occurredOn: "2026-06-01")]
        let cache = CachingMomentRepository(wrapping: stub, refreshTTL: 0)

        _ = try await cache.moments(userId: "u")
        stub.stored.append(makeMoment(id: "cross", occurredOn: "2026-07-02"))
        _ = try await cache.moments(userId: "u")
        await cache.refreshTask?.value

        let refreshed = try await cache.moments(userId: "u")
        #expect(refreshed.map(\.id).contains("cross"))
    }
}
