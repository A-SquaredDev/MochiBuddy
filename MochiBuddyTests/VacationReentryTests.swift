//
//  VacationReentryTests.swift
//  MochiBuddyTests
//
//  Vacation mode's promise: while you're away Mochi will not pester you,
//  and you will not come back to a punished pet. These tests pin the
//  re-entry mechanics: the came-due-while-away bucket, the grace buffer,
//  the streak freeze, the open-ended check-in, and the triage flows.
//
//  Dates.now anchor: Wed 8 Jul 2026, 10:00 local.
//

import Foundation
import Testing
@testable import MochiBuddy

@MainActor
private func makeService(
    profile: UserProfile,
    tasks: [TaskItem] = []
) -> (VacationReentryService, StubProfileRepository, StubTaskRepository, StubComfortBufferStore, StubRelay, UserDefaults) {
    let profileRepo = StubProfileRepository()
    profileRepo.profile = profile
    let taskRepo = StubTaskRepository()
    taskRepo.incomplete = tasks
    let buffer = StubComfortBufferStore()
    let relay = StubRelay()
    let defaults = UserDefaults(suiteName: "vacation-tests-\(UUID())")!
    let service = VacationReentryService(
        profileRepository: profileRepo,
        taskRepository: taskRepo,
        bufferStore: buffer,
        relay: relay,
        defaults: defaults
    )
    return (service, profileRepo, taskRepo, buffer, relay, defaults)
}

@Suite("VacationReentryService · the bucket")
@MainActor
struct VacationBucketTests {

    @Test("re-entry buckets exactly the one-off tasks overdue at the trip's end")
    func bucketMembership() async {
        // Trip: started 10 days ago, ended yesterday 10:00.
        let profile = makeProfile(
            streak: 0,
            vacationMode: true,
            vacationResumeAt: Dates.days(-1),
            vacationStartedAt: Dates.days(-10)
        )
        let tasks = [
            makeTask(id: "duringTrip", dueAt: Dates.days(-3), hasTime: true),
            makeTask(id: "beforeTrip", dueAt: Dates.days(-12), hasTime: true),
            makeTask(id: "habit", dueAt: Dates.days(-2), hasTime: true, repeatRule: .daily),
            makeTask(id: "afterEnd", dueAt: Dates.hours(-12), hasTime: true),
            makeTask(id: "future", dueAt: Dates.days(2), hasTime: true),
            makeTask(id: "undated"),
        ]
        let (service, profileRepo, _, _, relay, _) = makeService(profile: profile, tasks: tasks)

        let processed = await service.processIfEnded(profile: profile, userId: "user1", now: Dates.now)

        #expect(processed)
        #expect(Set(service.pendingTriageIds()) == ["duringTrip", "beforeTrip"],
                "one-offs overdue at the end - recurring, post-end, future, undated all stay out")
        #expect(profileRepo.savedVacations.last.map { $0.mode == false && $0.resumeAt == nil && $0.startedAt == nil } == true,
                "the mode is fully cleared")
        #expect(relay.triggers.contains(.vacationChange))
    }

    @Test("a still-active vacation is untouched - re-entry only fires once it truly ended")
    func stillActiveIsNoOp() async {
        let profile = makeProfile(
            vacationMode: true,
            vacationResumeAt: Dates.days(2),
            vacationStartedAt: Dates.days(-1)
        )
        let (service, profileRepo, _, _, _, _) = makeService(profile: profile)
        let processed = await service.processIfEnded(profile: profile, userId: "user1", now: Dates.now)
        #expect(!processed)
        #expect(profileRepo.savedVacations.isEmpty)
        #expect(service.pendingTriageIds().isEmpty)
    }

    @Test("the 30-day cap ends an open-ended trip, and the bucket window stops at the cap")
    func capEndsOpenEnded() async {
        // Started 31 days ago: the cap landed yesterday. A task that came
        // due after the cap is not the vacation's fault.
        let profile = makeProfile(
            vacationMode: true,
            vacationStartedAt: Dates.days(-31)
        )
        let tasks = [
            makeTask(id: "duringTrip", dueAt: Dates.days(-5), hasTime: true),
            makeTask(id: "afterCap", dueAt: Dates.hours(-3), hasTime: true),
        ]
        let (service, _, _, _, _, _) = makeService(profile: profile, tasks: tasks)

        let processed = await service.processIfEnded(profile: profile, userId: "user1", now: Dates.now)

        #expect(processed)
        #expect(service.pendingTriageIds() == ["duringTrip"])
    }

    @Test("a manual end routes through the same re-entry")
    func manualEnd() async {
        let profile = makeProfile(
            vacationMode: true,
            vacationStartedAt: Dates.days(-3)
        )
        let tasks = [makeTask(id: "duringTrip", dueAt: Dates.days(-1), hasTime: true)]
        let (service, profileRepo, _, _, _, _) = makeService(profile: profile, tasks: tasks)

        await service.endNow(userId: "user1", now: Dates.now)

        #expect(service.pendingTriageIds() == ["duringTrip"])
        #expect(profileRepo.savedVacations.last?.mode == false)

        // Ending again is a no-op - the mode is already off.
        await service.endNow(userId: "user1", now: Dates.now)
        #expect(profileRepo.savedVacations.count == 1)
    }
}

@Suite("VacationReentryService · grace & streak")
@MainActor
struct VacationGraceTests {

    @Test("the grace buffer wakes Mochi at ~content and drifts over 24h - sized to the real pile")
    func graceBufferSeeded() async {
        let profile = makeProfile(
            vacationMode: true,
            vacationResumeAt: Dates.hours(-2),
            vacationStartedAt: Dates.days(-7)
        )
        let tasks = [
            makeTask(id: "a", dueAt: Dates.days(-4), hasTime: true, priority: .high),
            makeTask(id: "b", dueAt: Dates.days(-3), hasTime: true, priority: .high),
        ]
        let (service, _, _, buffer, _, _) = makeService(profile: profile, tasks: tasks)

        _ = await service.processIfEnded(profile: profile, userId: "user1", now: Dates.now)

        let baseline = MoodEngine.baseline(
            incompleteTasks: tasks, completionsLast24h: 0, vacationMode: false, now: Dates.now
        )
        let expected = min(MoodEngine.Constants.bufferCap, MoodEngine.Constants.anchor - baseline)
        #expect(buffer.boosts.count == 1)
        if let boost = buffer.boosts.first {
            #expect(abs(boost.lift - expected) < 0.5, "lift covers the gap to the content anchor")
            #expect(boost.duration == VacationConstants.graceDecay)
        }
    }

    @Test("nothing due means no grace needed - Mochi already wakes content")
    func noGraceWhenContent() async {
        let profile = makeProfile(
            vacationMode: true,
            vacationResumeAt: Dates.hours(-2),
            vacationStartedAt: Dates.days(-7)
        )
        let (service, _, _, buffer, _, _) = makeService(profile: profile)
        _ = await service.processIfEnded(profile: profile, userId: "user1", now: Dates.now)
        #expect(buffer.boosts.isEmpty)
    }

    @Test("the streak froze, it never broke: lastActive jumps to yesterday so today continues the chain")
    func streakResumesUnchanged() async {
        let profile = makeProfile(
            streak: 12,
            bestStreak: 20,
            lastActiveDate: Dates.days(-9),
            vacationMode: true,
            vacationResumeAt: Dates.hours(-2),
            vacationStartedAt: Dates.days(-8)
        )
        let (service, profileRepo, _, _, _, _) = makeService(profile: profile)
        _ = await service.processIfEnded(profile: profile, userId: "user1", now: Dates.now)

        let saved = profileRepo.savedStreaks.last
        #expect(saved?.count == 12, "resumes unchanged - never re-earned, never broken")
        #expect(saved?.best == 20)
        let yesterday = Dates.calendar.date(byAdding: .day, value: -1, to: Dates.startOfToday)
        #expect(saved.map { Dates.calendar.startOfDay(for: $0.lastActiveDate) } == yesterday)
    }

    @Test("a completion during the trip already kept the chain alive - no bump needed")
    func freshStreakUntouched() async {
        let profile = makeProfile(
            streak: 12,
            lastActiveDate: Dates.startOfToday,
            vacationMode: true,
            vacationResumeAt: Dates.hours(-2),
            vacationStartedAt: Dates.days(-8)
        )
        let (service, profileRepo, _, _, _, _) = makeService(profile: profile)
        _ = await service.processIfEnded(profile: profile, userId: "user1", now: Dates.now)
        #expect(profileRepo.savedStreaks.isEmpty)
    }
}

@Suite("VacationReentryService · long-run check-in")
@MainActor
struct VacationCheckInTests {

    @Test("the gentle card is due two weeks into an open-ended trip, snoozes for another interval, and never nags a fixed-date trip")
    func checkInRules() async {
        let openEnded = makeProfile(vacationMode: true, vacationStartedAt: Dates.days(-15))
        let (service, _, _, _, _, _) = makeService(profile: openEnded)

        #expect(service.checkInDue(profile: openEnded, now: Dates.now))

        let young = makeProfile(vacationMode: true, vacationStartedAt: Dates.days(-10))
        #expect(!service.checkInDue(profile: young, now: Dates.now))

        var fixed = openEnded
        fixed.vacationResumeAt = Dates.days(5)
        #expect(!service.checkInDue(profile: fixed, now: Dates.now), "a chosen end date needs no check-in")

        service.snoozeCheckIn(now: Dates.now)
        #expect(!service.checkInDue(profile: openEnded, now: Dates.now), "'keep resting' re-arms the interval")
    }
}

@Suite("VacationViewModel · entry & exit")
@MainActor
struct VacationEntryTests {

    private func makeVM(
        profile: UserProfile
    ) -> (VacationViewModel, StubProfileRepository) {
        let (service, profileRepo, _, _, _, _) = makeService(profile: profile)
        let vm = VacationViewModel(
            authRepository: StubAuthRepository(),
            profileRepository: profileRepo,
            relay: StubRelay(),
            reentryService: service
        )
        return (vm, profileRepo)
    }

    @Test("turning vacation on records when the trip began")
    func entryRecordsStart() async {
        let (vm, profileRepo) = makeVM(profile: makeProfile())
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.setVacation(true))

        let saved = profileRepo.savedVacations.last
        #expect(saved?.mode == true)
        #expect(saved?.startedAt != nil, "startedAt drives the cap, the check-in, and the bucket")
    }

    @Test("the fixed-date picker defaults to a week out")
    func defaultTripLength() async {
        let (vm, _) = makeVM(profile: makeProfile())
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.setVacation(true))
        await vm.triggerAsync(.setAutoResume(true))

        let expected = Dates.calendar.date(
            byAdding: .day, value: VacationConstants.defaultDays,
            to: Dates.calendar.startOfDay(for: .now)
        )
        #expect(vm.uiState.resumeDate == expected)
    }

    @Test("turning it off routes through re-entry, never a bare flag flip")
    func exitRoutesThroughReentry() async {
        let (vm, profileRepo) = makeVM(
            profile: makeProfile(vacationMode: true, vacationStartedAt: Dates.days(-1))
        )
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.turnOffTapped)

        let saved = profileRepo.savedVacations.last
        #expect(saved?.mode == false)
        #expect(saved?.startedAt == nil)
    }
}

@Suite("HomeViewModel · vacation surfaces")
@MainActor
struct HomeVacationTests {

    @Test("an active fixed-date vacation pins the resting pose, shows the dated banner, hides mood chrome")
    func activeVacationSurface() async {
        // HomeViewModel reads the real clock - fixture dates must too.
        let (vm, _, _, _) = makeHomeVMOnVacation(
            resumeAt: Date.now.addingTimeInterval(3 * 24 * 3600),
            startedAt: Date.now.addingTimeInterval(-2 * 24 * 3600)
        )
        await vm.triggerAsync(.refresh)

        #expect(vm.uiState.isOnVacation)
        #expect(vm.uiState.isSleeping, "resting pose is pinned regardless of buffer or tasks")
        #expect(vm.uiState.vacationBanner?.contains("back") == true)
        #expect(vm.uiState.moodTitle == "Mochi is resting")
        #expect(!vm.uiState.showTriage)
    }

    @Test("open-ended reads as back-whenever, and two weeks in the check-in card appears")
    func openEndedSurface() async {
        let (vm, _, _, _) = makeHomeVMOnVacation(
            resumeAt: nil,
            startedAt: Date.now.addingTimeInterval(-15 * 24 * 3600)
        )
        await vm.triggerAsync(.refresh)

        #expect(vm.uiState.vacationBanner == "On vacation · back whenever you're ready")
        #expect(vm.uiState.showVacationCheckIn)
    }

    @Test("a vacation that ended while away runs re-entry on refresh: banner gone, triage up")
    func endedWhileAwayTriage() async {
        let (vm, _, _, _) = makeHomeVMOnVacation(
            resumeAt: Dates.hours(-2),
            startedAt: Dates.days(-7),
            tasks: [
                makeTask(id: "bill", title: "Pay water bill", dueAt: Dates.days(-3), hasTime: true),
                makeTask(id: "future", dueAt: Dates.days(4), hasTime: true),
            ]
        )
        await vm.triggerAsync(.refresh)

        #expect(vm.uiState.vacationBanner == nil)
        #expect(!vm.uiState.isOnVacation)
        #expect(vm.uiState.showTriage)
        #expect(vm.uiState.triageItems.map(\.id) == ["bill"])
        #expect(vm.uiState.triageItems.first?.title == "Pay water bill")
    }

    @Test("complete-all pays coins for every bucket task and closes the sheet")
    func triageCompleteAll() async {
        let (vm, taskRepo, _, _) = makeHomeVMOnVacation(
            resumeAt: Dates.hours(-2),
            startedAt: Dates.days(-7),
            tasks: [
                makeTask(id: "a", dueAt: Dates.days(-3), hasTime: true),
                makeTask(id: "b", dueAt: Dates.days(-2), hasTime: true),
            ]
        )
        await vm.triggerAsync(.refresh)
        let coinsBefore = vm.uiState.coins

        await vm.triggerAsync(.triageCompleteAll)

        #expect(vm.uiState.coins == coinsBefore + 2 * RewardsStore.coinsPerTask)
        #expect(taskRepo.setCompletedCalls.map(\.taskId).sorted() == ["a", "b"])
        #expect(!vm.uiState.showTriage)
        #expect(vm.uiState.doneTodayItems.count == 2)
    }

    @Test("reschedule-all spreads the pile across the coming days instead of re-piling it")
    func triageRescheduleAll() async {
        let (vm, taskRepo, _, _) = makeHomeVMOnVacation(
            resumeAt: Dates.hours(-2),
            startedAt: Dates.days(-7),
            tasks: (0..<3).map { i in
                makeTask(id: "t\(i)", dueAt: Dates.days(-2), hasTime: true)
            }
        )
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.triageRescheduleAll)

        #expect(taskRepo.updatedTasks.count == 3)
        let days = Set(taskRepo.updatedTasks.compactMap(\.dueAt))
        #expect(days.count == 3, "each lands on its own day")
        #expect(days.allSatisfy { $0 > Dates.calendar.startOfDay(for: .now) })
        #expect(!vm.uiState.showTriage)
    }

    @Test("dismiss-all deletes the never-mind pile; Later just closes and clears")
    func triageDismissAndLater() async {
        let (vm, taskRepo, _, _) = makeHomeVMOnVacation(
            resumeAt: Dates.hours(-2),
            startedAt: Dates.days(-7),
            tasks: [makeTask(id: "a", dueAt: Dates.days(-3), hasTime: true)]
        )
        await vm.triggerAsync(.refresh)
        await vm.triggerAsync(.triageDismissAll)
        #expect(taskRepo.deletedIds == ["a"])
        #expect(!vm.uiState.showTriage)

        // A second refresh must not resurrect the sheet.
        await vm.triggerAsync(.refresh)
        #expect(!vm.uiState.showTriage)
    }
}

@MainActor
private func makeHomeVMOnVacation(
    resumeAt: Date?,
    startedAt: Date? = Dates.days(-2),
    tasks: [TaskItem] = []
) -> (HomeViewModel, StubTaskRepository, StubProfileRepository, StubComfortBufferStore) {
    makeHomeVMForVacation(
        profile: makeProfile(
            coins: 100, streak: 4,
            vacationMode: true,
            vacationResumeAt: resumeAt,
            vacationStartedAt: startedAt
        ),
        tasks: tasks
    )
}

@MainActor
private func makeHomeVMForVacation(
    profile: UserProfile,
    tasks: [TaskItem]
) -> (HomeViewModel, StubTaskRepository, StubProfileRepository, StubComfortBufferStore) {
    let auth = StubAuthRepository()
    let profileRepo = StubProfileRepository()
    profileRepo.profile = profile
    let taskRepo = StubTaskRepository()
    taskRepo.incomplete = tasks
    let listRepo = StubListRepository()
    let buffer = StubComfortBufferStore()
    let membership = MembershipSession()
    let reentry = VacationReentryService(
        profileRepository: profileRepo,
        taskRepository: taskRepo,
        bufferStore: buffer,
        relay: StubRelay(),
        defaults: UserDefaults(suiteName: "home-vacation-\(UUID())")!
    )
    let vm = HomeViewModel(
        authRepository: auth,
        profileRepository: profileRepo,
        taskRepository: taskRepo,
        listRepository: listRepo,
        bufferStore: buffer,
        rewardsStore: RewardsStore(profileRepository: profileRepo),
        completionStore: TaskCompletionStore(
            taskRepository: taskRepo,
            rewardsStore: RewardsStore(profileRepository: profileRepo),
            membershipSession: membership
        ),
        membershipSession: membership,
        recurrenceRoller: RecurrenceRoller(taskRepository: taskRepo),
        relay: StubRelay(),
        reentryService: reentry
    )
    return (vm, taskRepo, profileRepo, buffer)
}
