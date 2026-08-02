//
//  FirstTaskViewModelTests.swift
//  MochiBuddyTests
//
//  The onboarding first task must land like every other capture path:
//  due today, optionally with a rough reminder slot. A first task that
//  falls into Someday and can never notify is a broken first impression.
//

import Foundation
import Testing
@testable import MochiBuddy

@MainActor
private func makeFirstTaskVM() -> (FirstTaskViewModel, StubTaskRepository) {
    let taskRepo = StubTaskRepository()
    let profileRepo = StubProfileRepository()
    let defaults = UserDefaults(suiteName: "first-task-\(UUID())")!
    let store = OnboardingStore(
        authRepository: StubAuthRepository(),
        profileRepository: profileRepo,
        taskRepository: taskRepo,
        themeStore: ThemeStore(defaults: defaults),
        petIdentityStore: PetIdentityStore(profileRepository: profileRepo, defaults: defaults)
    )
    return (FirstTaskViewModel(onboardingStore: store), taskRepo)
}

@Suite("FirstTask · due today with a rough slot")
@MainActor
struct FirstTaskViewModelTests {

    @Test("no slot chosen: the task is still seeded due today, date-only")
    func defaultSeedsDueToday() async {
        let (vm, taskRepo) = makeFirstTaskVM()
        await vm.triggerAsync(.titleChanged("Water the plants"))
        await vm.triggerAsync(.addTapped)

        let draft = try! #require(taskRepo.addedDrafts.first)
        #expect(draft.title == "Water the plants")
        #expect(draft.dueAt == Calendar.current.startOfDay(for: .now))
        #expect(draft.hasTime == false)
    }

    @Test("a slot chip stamps the matching time onto today")
    func slotChipAddsTime() async {
        let (vm, taskRepo) = makeFirstTaskVM()
        await vm.triggerAsync(.titleChanged("Call mum"))
        await vm.triggerAsync(.timeChoiceTapped(.evening))
        await vm.triggerAsync(.addTapped)

        let draft = try! #require(taskRepo.addedDrafts.first)
        let expected = Calendar.current.date(
            bySettingHour: 18, minute: 0, second: 0,
            of: Calendar.current.startOfDay(for: .now)
        )
        #expect(draft.dueAt == expected)
        #expect(draft.hasTime == true)
    }

    @Test("switching back to No time drops the slot again")
    func noTimeRevertsToDateOnly() async {
        let (vm, taskRepo) = makeFirstTaskVM()
        await vm.triggerAsync(.titleChanged("Pay rent"))
        await vm.triggerAsync(.timeChoiceTapped(.morning))
        await vm.triggerAsync(.timeChoiceTapped(.noTime))
        await vm.triggerAsync(.addTapped)

        let draft = try! #require(taskRepo.addedDrafts.first)
        #expect(draft.hasTime == false)
        #expect(draft.dueAt == Calendar.current.startOfDay(for: .now))
    }
}
