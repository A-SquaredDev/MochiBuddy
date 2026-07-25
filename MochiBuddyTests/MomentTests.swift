//
//  MomentTests.swift
//  MochiBuddyTests
//
//  Feature 6, the moment record: natural ids identify events (never
//  categories), payloads derive deterministically from immutable event
//  facts, adoption is atomic with its synthesis fallback, and producers
//  respect the lapse silence.
//

import Foundation
import Testing
@testable import MochiBuddy

private let locale = Locale(identifier: "en_US")

@Suite("Moments · identity + payloads")
@MainActor
struct MomentIdentityTests {

    @Test("the exhaustive natural-id table (spec v1)")
    func naturalIdTable() {
        #expect(MomentFactory.adoption(
            adoptedOn: "2026-07-08", petName: nil, locale: locale, now: Dates.now
        ).id == "adoption-2026-07-08")

        let month = AnniversaryMilestone(tier: .month, day: CivilDay("2026-08-08")!)
        #expect(MomentFactory.anniversary(month, locale: locale, now: Dates.now).id
            == "anniversary-month-2026-08-08")
        let year2 = AnniversaryMilestone(tier: .year(2), day: CivilDay("2028-07-08")!)
        #expect(MomentFactory.anniversary(year2, locale: locale, now: Dates.now).id
            == "anniversary-year2-2028-07-08")

        #expect(MomentFactory.streakMilestone(
            count: 30, day: "2026-07-12", petName: "Nori", locale: locale, now: Dates.now
        ).id == "streak-milestone-30-2026-07-12")

        let start = Date(timeIntervalSince1970: 1_780_000_000)
        #expect(MomentFactory.vacationReturn(
            intervalStart: start, endDay: "2026-06-20", petName: "Nori",
            locale: locale, now: Dates.now
        ).id == "vacation-return-1780000000")

        #expect(MomentFactory.listReturn(
            listId: "listA", firedOn: "2026-07-05", listName: "Reading",
            locale: locale, now: Dates.now
        ).id == "list-return-listA-2026-07-05")
    }

    @Test("a rebuilt streak reaching the same count is a NEW moment; two same-date vacations differ by interval start")
    func eventsNotCategories() {
        let first = MomentFactory.streakMilestone(
            count: 30, day: "2026-03-01", petName: "Nori", locale: locale, now: Dates.now
        )
        let rebuilt = MomentFactory.streakMilestone(
            count: 30, day: "2026-07-12", petName: "Nori", locale: locale, now: Dates.now
        )
        #expect(first.id != rebuilt.id)

        let morning = MomentFactory.vacationReturn(
            intervalStart: Dates.hours(-30), endDay: "2026-07-07", petName: "Nori",
            locale: locale, now: Dates.now
        )
        let afternoon = MomentFactory.vacationReturn(
            intervalStart: Dates.hours(-10), endDay: "2026-07-07", petName: "Nori",
            locale: locale, now: Dates.now
        )
        #expect(morning.id != afternoon.id)
        #expect(morning.occurredOn == afternoon.occurredOn)
    }

    @Test("racing writers derive content-identical payloads from the same facts (edge 3)")
    func payloadDeterminism() {
        let a = MomentFactory.listReturn(
            listId: "listA", firedOn: "2026-07-05", listName: "Reading",
            locale: locale, now: Dates.now
        )
        let b = MomentFactory.listReturn(
            listId: "listA", firedOn: "2026-07-05", listName: "Reading",
            locale: locale, now: Dates.now
        )
        #expect(a == b)
        #expect(a.renderedTextSnapshot == "You found your way back to Reading.")
        #expect(a.subjectNameSnapshot == "Reading")
        #expect(a.sourceEventId == "listReturn:listA|2026-07-05")
    }

    @Test("adoption copy branches: captured name vs legacy-neutral, which never implies a name")
    func adoptionCopy() {
        let named = MomentFactory.adoption(
            adoptedOn: "2026-07-23", petName: "Nori", locale: locale, now: Dates.now
        )
        #expect(named.renderedTextSnapshot == "You brought Nori home.")
        #expect(named.petNameSnapshot == "Nori")

        let legacy = MomentFactory.adoption(
            adoptedOn: "2026-06-28", petName: nil, locale: locale, now: Dates.now
        )
        #expect(legacy.renderedTextSnapshot == "The day your story began.")
        #expect(legacy.petNameSnapshot == nil)
        #expect(!legacy.renderedTextSnapshot.contains("Mochi"),
                "a backfilled adoption never implies the current name was used then")
    }

    @Test("moment copy carries no em dashes and no emoji")
    func copyStyle() {
        let samples = [
            MomentCopy.adoption(petName: "Nori"),
            MomentCopy.adoptionLegacy,
            MomentCopy.anniversary(tier: .week),
            MomentCopy.anniversary(tier: .month),
            MomentCopy.anniversary(tier: .year(1)),
            MomentCopy.anniversary(tier: .year(3)),
            MomentCopy.streakMilestone(count: 7, petName: "Nori"),
            MomentCopy.streakMilestone(count: 250, petName: "Nori"),
            MomentCopy.vacationReturn(petName: "Nori"),
            MomentCopy.listReturn(listName: "Errands"),
        ]
        for line in samples {
            #expect(!line.contains("\u{2014}"))
            #expect(line.unicodeScalars.allSatisfy { $0.value < 0x1F000 })
        }
        #expect(MomentCopy.streakMilestone(count: 30, petName: "Nori")
            == "Thirty days in a row with Nori.")
    }

    @Test("accessibility text appends the spoken event date")
    func accessibilityText() {
        let moment = MomentFactory.streakMilestone(
            count: 7, day: "2026-07-12", petName: "Nori", locale: locale, now: Dates.now
        )
        #expect(moment.accessibilityTextSnapshot == "Seven days in a row with Nori. July 12, 2026.")
    }

    @Test("field round-trip through the Firestore encoding")
    func fieldsRoundTrip() {
        let moment = MomentFactory.listReturn(
            listId: "listA", firedOn: "2026-07-05", listName: "Reading",
            locale: locale, now: Dates.now
        )
        let decoded = MomentFields.moment(id: moment.id, data: MomentFields.fields(for: moment))
        #expect(decoded == moment)
    }
}

@Suite("Moments · writer")
@MainActor
struct MomentWriterTests {

    private func makeWriter(
        session: MembershipSession? = nil,
        lists: [TaskList] = []
    ) -> (MomentWriter, StubMomentRepository, StubProfileRepository) {
        let session = session ?? MembershipSession()
        let profileRepo = StubProfileRepository()
        let momentRepo = StubMomentRepository()
        let listRepo = StubListRepository()
        listRepo.lists = lists
        let defaults = UserDefaults(suiteName: "momentWriterTests-\(UUID().uuidString)")!
        let identity = PetIdentityStore(profileRepository: profileRepo, defaults: defaults)
        let writer = MomentWriter(
            authRepository: StubAuthRepository(),
            momentRepository: momentRepo,
            petIdentityStore: identity,
            listRepository: listRepo,
            membershipSession: session,
            calendar: Dates.calendar
        )
        return (writer, momentRepo, profileRepo)
    }

    @Test("streak milestone writes once; the natural key absorbs repeats")
    func streakMilestoneIdempotent() async {
        let (writer, repo, _) = makeWriter()
        await writer.streakMilestone(count: 7, now: Dates.now)
        await writer.streakMilestone(count: 7, now: Dates.now)
        #expect(repo.stored.count == 1)
        #expect(repo.stored.first?.id == "streak-milestone-7-2026-07-08")
    }

    @Test("nothing composes during lapse: every producer no-ops (synthesis repair excepted)")
    func lapseGate() async {
        let session = MembershipSession()
        session.status = .lapsed
        let (writer, repo, _) = makeWriter(session: session)
        await writer.streakMilestone(count: 7, now: Dates.now)
        await writer.anniversary(
            AnniversaryMilestone(tier: .month, day: CivilDay("2026-08-08")!), now: Dates.now
        )
        await writer.vacationEnded(
            intervalStart: Dates.days(-10), end: Dates.now, adoptedOn: "2026-06-01", now: Dates.now
        )
        #expect(repo.stored.isEmpty)

        // The adoption repair records an existing fact, composes nothing.
        await writer.ensureAdoptionMoment(adoptedOn: "2026-06-01", now: Dates.now)
        #expect(repo.stored.map(\.id) == ["adoption-2026-06-01"])
    }

    @Test("vacation re-entry writes the return moment plus deferrable anniversaries on their TRUE dates")
    func vacationEndProducesDeferredAnniversaries() async {
        let (writer, repo, _) = makeWriter()
        // Adoption 2026-06-05; the month mark (Jul 5) falls inside a trip
        // from Jun 28 to Jul 7. The week mark (Jun 12) predates the trip.
        let start = Dates.days(-10) // Jun 28
        let end = Dates.days(-1)    // Jul 7
        await writer.vacationEnded(
            intervalStart: start, end: end, adoptedOn: "2026-06-05", now: Dates.now
        )
        let ids = Set(repo.stored.map(\.id))
        #expect(ids.contains("vacation-return-\(Int(start.timeIntervalSince1970))"))
        #expect(ids.contains("anniversary-month-2026-07-05"))
        #expect(repo.stored.count == 2)
        let anniversary = repo.stored.first { $0.type == .anniversary }
        #expect(anniversary?.occurredOn == "2026-07-05",
                "deferred acknowledgment records the mark's true date")
    }

    @Test("list return freezes the list's name at emission; unknown list stays silent")
    func listReturnSnapshotsName() async {
        let lists = [TaskList(id: "listA", name: "Reading", colorHex: "#AABBCC", icon: "book", order: 0)]
        let (writer, repo, _) = makeWriter(lists: lists)
        let observation = QualifiedObservation(
            kind: .listReturn, conclusion: .listReturn(listId: "listA"), stableSince: "2026-07-05"
        )
        await writer.listReturn(observation, now: Dates.now)
        #expect(repo.stored.first?.subjectNameSnapshot == "Reading")
        #expect(repo.stored.first?.sourceEventId == "listReturn:listA|2026-07-05")

        let gone = QualifiedObservation(
            kind: .listReturn, conclusion: .listReturn(listId: "deleted"), stableSince: "2026-07-05"
        )
        await writer.listReturn(gone, now: Dates.now)
        #expect(repo.stored.count == 1, "no list, no name to freeze, no moment")
    }
}

@Suite("Moments · adoption atomicity")
@MainActor
struct AdoptionAtomicityTests {

    @Test("the naming beat stamps adoptedOn and the NAMED adoption moment in one repository call")
    func onboardingBatch() async {
        let repo = StubProfileRepository()
        let defaults = UserDefaults(suiteName: "adoptionTests-\(UUID().uuidString)")!
        let store = PetIdentityStore(profileRepository: repo, defaults: defaults)
        await store.completeNamingBeat(rawName: "Nori", userId: "user1", now: Dates.now)

        #expect(repo.stampedAdoptedOns == [AdoptedOnDate.string(from: Dates.now, in: .current)])
        #expect(repo.stampedAdoptionMoments.count == 1)
        let moment = repo.stampedAdoptionMoments.first
        #expect(moment?.type == .adoption)
        #expect(moment?.petNameSnapshot == "Nori")
        #expect(moment?.renderedTextSnapshot == "You brought Nori home.")
    }

    @Test("the migration backfill writes the legacy-neutral moment, no name implied")
    func backfillIsLegacyNeutral() async {
        let repo = StubProfileRepository()
        repo.profile = makeProfile(createdAt: Dates.days(-40), mochiName: "Nori")
        let defaults = UserDefaults(suiteName: "adoptionTests-\(UUID().uuidString)")!
        let store = PetIdentityStore(profileRepository: repo, defaults: defaults)
        await store.load(profile: repo.profile!, now: Dates.now)

        #expect(repo.stampedAdoptionMoments.count == 1)
        let moment = repo.stampedAdoptionMoments.first
        #expect(moment?.petNameSnapshot == nil)
        #expect(moment?.renderedTextSnapshot == "The day your story began.")
        #expect(moment?.occurredOn == AdoptedOnDate.string(from: Dates.days(-40), in: .current))
    }
}
