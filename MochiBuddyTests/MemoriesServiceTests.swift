//
//  MemoriesServiceTests.swift
//  MochiBuddyTests
//
//  The Feature 2 orchestrator: the anniversary banner's guards (once per
//  milestone, streak collision, vacation, lapse), the Personal-Layer
//  assignment commit (idempotent re-lays, opener rendering, crushed
//  override), and the callback_evaluated denominator throttle.
//

import Foundation
import Testing
@testable import MochiBuddy

@MainActor
private final class RecordingCallbackTelemetry: CallbackTelemetry {
    private(set) var events: [CallbackTelemetryEvent] = []
    func log(_ event: CallbackTelemetryEvent) { events.append(event) }

    var anniversaryShown: [(tier: String, surface: String)] {
        events.compactMap {
            if case .anniversaryShown(let tier, let surface) = $0 { (tier, surface) } else { nil }
        }
    }

    var evaluatedCount: Int {
        events.count { if case .callbackEvaluated = $0 { true } else { false } }
    }
}

@MainActor
struct MemoriesServiceTests {

    private struct World {
        let service: MemoriesService
        let profileRepo: StubProfileRepository
        let taskRepo: StubTaskRepository
        let celebrationCenter: CelebrationCenter
        let membershipSession: MembershipSession
        let telemetry: RecordingCallbackTelemetry
        let callbackLedger: CallbackLedger
    }

    private func makeWorld(profile: UserProfile) -> World {
        let name = "memories-service-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        let auth = StubAuthRepository()
        let profileRepo = StubProfileRepository()
        profileRepo.profile = profile
        let taskRepo = StubTaskRepository()
        let observationLedger = ObservationLedger(defaults: defaults)
        let observationService = ObservationService(
            authRepository: auth,
            profileRepository: profileRepo,
            taskRepository: taskRepo,
            listRepository: StubListRepository(),
            ledger: observationLedger
        )
        let callbackLedger = CallbackLedger(defaults: defaults)
        let membershipSession = MembershipSession()
        let celebrationCenter = CelebrationCenter()
        let telemetry = RecordingCallbackTelemetry()
        let service = MemoriesService(
            authRepository: auth,
            profileRepository: profileRepo,
            observationService: observationService,
            observationLedger: observationLedger,
            ledger: callbackLedger,
            membershipSession: membershipSession,
            celebrationCenter: celebrationCenter,
            telemetry: telemetry,
            calendar: Dates.calendar
        )
        return World(
            service: service, profileRepo: profileRepo, taskRepo: taskRepo,
            celebrationCenter: celebrationCenter, membershipSession: membershipSession,
            telemetry: telemetry, callbackLedger: callbackLedger
        )
    }

    /// Dates.now is Wed 2026-07-08; adoption on 2026-07-01 makes it the
    /// 1-week anniversary.
    private let anniversaryProfile = makeProfile(adoptedOn: "2026-07-01")

    // MARK: - Banner

    @Test func bannerPostsOncePerMilestone() async {
        let world = makeWorld(profile: anniversaryProfile)
        await world.service.checkAnniversaryBanner(now: Dates.now)
        let text = world.celebrationCenter.consumeAnniversary()
        #expect(text?.contains("One week") == true)
        #expect(text?.contains("Mochi") == true)
        #expect(world.telemetry.anniversaryShown.map(\.surface) == ["banner"])

        // A later open the same day: once per milestone, per the ledger.
        await world.service.checkAnniversaryBanner(now: Dates.hours(3))
        #expect(world.celebrationCenter.consumeAnniversary() == nil)
    }

    @Test func bannerSkippedOnNonMilestoneDays() async {
        let world = makeWorld(profile: makeProfile(adoptedOn: "2026-07-03"))
        await world.service.checkAnniversaryBanner(now: Dates.now)
        #expect(world.celebrationCenter.consumeAnniversary() == nil)
    }

    @Test func streakClaimedDateSuppressesTheBanner() async {
        // Streak 6 continuing into today: day 7 is reachable, the streak
        // owns the date (edge case 1).
        let yesterday = Dates.calendar.date(byAdding: .day, value: -1, to: Dates.now)!
        let world = makeWorld(profile: makeProfile(
            streak: 6, bestStreak: 6, lastActiveDate: yesterday, adoptedOn: "2026-07-01"
        ))
        await world.service.checkAnniversaryBanner(now: Dates.now)
        #expect(world.celebrationCenter.consumeAnniversary() == nil)
        #expect(world.telemetry.anniversaryShown.isEmpty)
    }

    @Test func vacationAndLapseSilenceTheBanner() async {
        var vacationing = anniversaryProfile
        vacationing.vacationMode = true
        vacationing.vacationStartedAt = Dates.hours(-24)
        vacationing.vacationResumeAt = Dates.hours(48)
        let onVacation = makeWorld(profile: vacationing)
        await onVacation.service.checkAnniversaryBanner(now: Dates.now)
        #expect(onVacation.celebrationCenter.consumeAnniversary() == nil)

        let lapsed = makeWorld(profile: anniversaryProfile)
        lapsed.membershipSession.status = .notSubscribed
        await lapsed.service.checkAnniversaryBanner(now: Dates.now)
        #expect(lapsed.celebrationCenter.consumeAnniversary() == nil)
    }

    // MARK: - Personal-Layer assignment

    private func rundown(daysFromNow: Int) -> PlannedNotification {
        let day = Dates.calendar.startOfDay(for: Dates.now)
        let fireAt = Dates.calendar.date(byAdding: .day, value: daysFromNow, to: day)!
            .addingTimeInterval(7 * 3600)
        return PlannedNotification(
            id: NotificationID.rundown(on: fireAt, calendar: Dates.calendar),
            kind: .rundown,
            fireAt: fireAt
        )
    }

    @Test func anniversaryOpenerIsAssignedRenderedAndIdempotent() async {
        let world = makeWorld(profile: anniversaryProfile)
        let today = CivilDay(of: Dates.now, in: Dates.calendar).dateString

        let first = await world.service.assignPersonalLayer(
            rundowns: [rundown(daysFromNow: 0)],
            snapshot: MoodSnapshot(capturedAt: Dates.hours(-2)),
            taper: TaperState(),
            completionTimes: [],
            now: Dates.hours(-2)
        )
        guard case .anniversary(let milestone)? = first[today]?.line else {
            Issue.record("expected the anniversary line, got \(String(describing: first[today]))")
            return
        }
        #expect(milestone.tier == .week)
        #expect(first[today]?.opener?.contains("One week") == true)
        #expect(first[today]?.opener?.contains("Mochi") == true)
        #expect(first[today]?.opener?.contains("{name}") == false)
        #expect(world.telemetry.anniversaryShown.map(\.surface) == ["rundown"])

        // A second re-lay with identical inputs changes nothing and does
        // NOT log or rotate again.
        let second = await world.service.assignPersonalLayer(
            rundowns: [rundown(daysFromNow: 0)],
            snapshot: MoodSnapshot(capturedAt: Dates.hours(-1)),
            taper: TaperState(),
            completionTimes: [],
            now: Dates.hours(-1)
        )
        #expect(second[today]?.opener == first[today]?.opener)
        #expect(world.telemetry.anniversaryShown.count == 1)
    }

    @Test func crushedYesterdayRidesThePriorityAndRendersNoOpener() async {
        // Plain profile, six completions yesterday: crushed wins the
        // slot as a title override (opener nil).
        let world = makeWorld(profile: makeProfile(adoptedOn: "2026-01-01"))
        let yesterday = Dates.hours(-20)
        let assignments = await world.service.assignPersonalLayer(
            rundowns: [rundown(daysFromNow: 0)],
            snapshot: MoodSnapshot(capturedAt: Dates.hours(-2)),
            taper: TaperState(),
            completionTimes: Array(repeating: yesterday, count: 6),
            now: Dates.hours(-2)
        )
        let today = CivilDay(of: Dates.now, in: Dates.calendar).dateString
        #expect(assignments[today]?.line == .crushedYesterday)
        #expect(assignments[today]?.opener == nil)
    }

    @Test func lapsedAssignsNothing() async {
        let world = makeWorld(profile: anniversaryProfile)
        world.membershipSession.status = .notSubscribed
        let assignments = await world.service.assignPersonalLayer(
            rundowns: [rundown(daysFromNow: 0)],
            snapshot: MoodSnapshot(capturedAt: Dates.now),
            taper: TaperState(),
            completionTimes: [],
            now: Dates.now
        )
        #expect(assignments.isEmpty)
    }

    @Test func evaluatedDenominatorThrottlesOncePerTypePerDay() async {
        let world = makeWorld(profile: makeProfile(adoptedOn: "2026-01-01"))
        _ = await world.service.assignPersonalLayer(
            rundowns: [rundown(daysFromNow: 0)],
            snapshot: MoodSnapshot(capturedAt: Dates.now),
            taper: TaperState(),
            completionTimes: [],
            now: Dates.now
        )
        #expect(world.telemetry.evaluatedCount == CallbackType.allCases.count)
        _ = await world.service.assignPersonalLayer(
            rundowns: [rundown(daysFromNow: 0)],
            snapshot: MoodSnapshot(capturedAt: Dates.hours(1)),
            taper: TaperState(),
            completionTimes: [],
            now: Dates.hours(1)
        )
        #expect(world.telemetry.evaluatedCount == CallbackType.allCases.count,
                "same civil day logs nothing new")
    }
}
