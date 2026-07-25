//
//  TaskEditorSuggestionTests.swift
//  MochiBuddyTests
//
//  The suggestion chip's editor lifecycle (Personal Layer, Feature 5):
//  session-frozen presentation, one presentation per trigger, manual
//  changes satisfying or removing the chip, the trigger-keyed dismissal
//  surviving reopen and the first save via the preallocated id, and the
//  save-based outcome classification with its precedence.
//
//  These run against the REAL wall clock (the editor is a live surface),
//  so fixtures anchor on today's civil day and due dates sit tomorrow -
//  the lead-time guard never races the suite.
//

import Foundation
import Testing
@testable import MochiBuddy

private final class RecordingSuggestionTelemetry: SuggestionTelemetry {
    private(set) var events: [SuggestionTelemetryEvent] = []
    func log(_ event: SuggestionTelemetryEvent) { events.append(event) }

    var outcomes: [(SuggestionTrigger, SuggestionScopeTier, SuggestionOutcome)] {
        events.compactMap {
            if case .outcome(let trigger, let tier, let outcome) = $0 {
                return (trigger, tier, outcome)
            }
            return nil
        }
    }
    var shownCount: Int {
        events.filter { if case .shown = $0 { return true } else { return false } }.count
    }
}

/// Civil date string `offset` days from the REAL today.
private func liveDay(_ offset: Int) -> String {
    CivilDay(of: .now, in: .current).advanced(by: offset).dateString
}

/// A rich, unimodal global history: 20 completions at 10:00 across the
/// last 20 days, distinct identities - qualifies everywhere it should.
private func richGlobalStats(minute: Int = 600) -> [CompletedTaskStat] {
    (0..<20).map { index in
        makeStat(
            taskId: "hist\(index)", localDate: liveDay(-1 - index), localMinute: minute,
            completedAt: Date.now.addingTimeInterval(TimeInterval(-(1 + index)) * 86_400)
        )
    }
}

/// Eight timed series completions at 20:00 across the last 8 days.
private func seriesStats(seriesId: String, minute: Int = 1200) -> [CompletedTaskStat] {
    (0..<8).map { index in
        makeStat(
            seriesId: seriesId, localDate: liveDay(-1 - index), localMinute: minute,
            completedAt: Date.now.addingTimeInterval(TimeInterval(-(1 + index)) * 86_400),
            hasTime: true, isRecurring: true
        )
    }
}

@MainActor
private func makeSuggestionEditorVM(
    editing: TaskItem? = nil,
    stats: [CompletedTaskStat],
    ledger: SuggestionLedger? = nil,
    lists: [TaskList] = []
) -> (vm: TaskEditorViewModel, repo: StubTaskRepository, telemetry: RecordingSuggestionTelemetry, ledger: SuggestionLedger) {
    let taskRepo = StubTaskRepository()
    taskRepo.completedStats = stats
    let listRepo = StubListRepository()
    listRepo.lists = lists
    let auth = StubAuthRepository()
    let profileRepo = StubProfileRepository()
    let observationService = ObservationService(
        authRepository: auth,
        profileRepository: profileRepo,
        taskRepository: taskRepo,
        listRepository: listRepo,
        ledger: ObservationLedger(defaults: freshSuggestionDefaults())
    )
    let telemetry = RecordingSuggestionTelemetry()
    let suggestionLedger = ledger ?? SuggestionLedger(defaults: freshSuggestionDefaults())
    let service = SuggestionService(
        authRepository: auth,
        profileRepository: profileRepo,
        taskRepository: taskRepo,
        observationService: observationService,
        membershipSession: MembershipSession(),
        ledger: suggestionLedger,
        telemetry: telemetry
    )
    let vm = TaskEditorViewModel(
        editingTask: editing,
        authRepository: auth,
        taskRepository: taskRepo,
        listRepository: listRepo,
        suggestionService: service
    )
    return (vm, taskRepo, telemetry, suggestionLedger)
}

private func freshSuggestionDefaults() -> UserDefaults {
    let name = "suggestion-editor-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

private let calendar = Calendar.current

// MARK: - New-time trigger

@Suite("TaskEditor · suggestions · new time")
@MainActor
struct TaskEditorNewTimeSuggestionTests {

    @Test("a rich history surfaces the chip for a dated, untimed task")
    func chipAppears() async {
        let (vm, _, telemetry, _) = makeSuggestionEditorVM(stats: richGlobalStats())
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.selectDateOption("tomorrow"))
        let chip = try! #require(vm.uiState.suggestionChip)
        #expect(chip.isConfirmed == false)
        #expect(chip.label.contains("10:00"))
        #expect(telemetry.shownCount == 1)
    }

    @Test("the presented proposal is frozen - field toggles never regenerate it")
    func frozenAcrossToggles() async {
        let (vm, _, telemetry, _) = makeSuggestionEditorVM(stats: richGlobalStats())
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.selectDateOption("tomorrow"))
        let label = vm.uiState.suggestionChip?.label
        await vm.triggerAsync(.selectPriority("high"))
        await vm.triggerAsync(.titleChanged("Water the plants"))
        await vm.triggerAsync(.selectRepeat("weekly"))
        #expect(vm.uiState.suggestionChip?.label == label)
        #expect(telemetry.shownCount == 1, "one presentation per trigger per session")
    }

    @Test("no evidence, no chip - the feature is simply absent")
    func silentWhenThin() async {
        let (vm, _, telemetry, _) = makeSuggestionEditorVM(
            stats: Array(richGlobalStats().prefix(5))
        )
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.selectDateOption("tomorrow"))
        #expect(vm.uiState.suggestionChip == nil)
        #expect(telemetry.shownCount == 0)
    }

    @Test("tap sets the time exactly as a manual pick would, then quiets down")
    func acceptFlow() async {
        let (vm, repo, telemetry, _) = makeSuggestionEditorVM(stats: richGlobalStats())
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.selectDateOption("tomorrow"))
        await vm.triggerAsync(.titleChanged("Water the plants"))
        await vm.triggerAsync(.suggestionTapped)

        #expect(vm.uiState.hasTime == true)
        #expect(vm.uiState.suggestionChip?.isConfirmed == true)
        #expect(vm.uiState.suggestionChip?.label.contains("set") == true)

        await vm.triggerAsync(.saveTapped)
        #expect(repo.addedDrafts.count == 1)
        let saved = repo.addedDrafts[0]
        #expect(saved.hasTime == true)
        let minute = calendar.component(.hour, from: saved.dueAt!) * 60
            + calendar.component(.minute, from: saved.dueAt!)
        #expect(minute == 600)
        #expect(repo.addedTaskIds == ["allocated-task-id"],
                "the save rides the preallocated id the dismissal ledger keys")
        #expect(telemetry.outcomes.map(\.2) == [.accepted])
    }

    @Test("a manual pick removes the offer; saving nearby classifies as matched")
    func manualMatch() async {
        let (vm, _, telemetry, _) = makeSuggestionEditorVM(stats: richGlobalStats())
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.selectDateOption("tomorrow"))
        await vm.triggerAsync(.titleChanged("Water the plants"))
        #expect(vm.uiState.suggestionChip != nil)

        // Manually choose 10:15 - within the +-30 circular matched window.
        await vm.triggerAsync(.timeTapped)
        let day = vm.uiState.date
        let manual = calendar.date(bySettingHour: 10, minute: 15, second: 0, of: day)!
        await vm.triggerAsync(.timeChanged(manual))
        #expect(vm.uiState.suggestionChip == nil, "a manual time satisfies or removes the offer")

        await vm.triggerAsync(.saveTapped)
        #expect(telemetry.outcomes.map(\.2) == [.matched])
    }

    @Test("dismiss hides for the session, records the ledger, and survives reopen AND the save")
    func dismissFlow() async {
        let ledger = SuggestionLedger(defaults: freshSuggestionDefaults())
        let (vm, repo, telemetry, _) = makeSuggestionEditorVM(stats: richGlobalStats(), ledger: ledger)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.selectDateOption("tomorrow"))
        await vm.triggerAsync(.titleChanged("Water the plants"))
        await vm.triggerAsync(.suggestionDismissed)
        #expect(vm.uiState.suggestionChip == nil)
        #expect(ledger.dismissedMinute(.newTime, id: "allocated-task-id", userId: "user1") == 600)

        await vm.triggerAsync(.saveTapped)
        #expect(telemetry.outcomes.map(\.2) == [.dismissed])

        // Reopen the saved task: the dismissal holds under the SAME id
        // because the save used the preallocated one.
        let savedTask = makeTask(
            id: repo.addedTaskIds[0]!,
            title: "Water the plants",
            dueAt: repo.addedDrafts[0].dueAt
        )
        let (reopened, _, reopenedTelemetry, _) = makeSuggestionEditorVM(
            editing: savedTask, stats: richGlobalStats(), ledger: ledger
        )
        await reopened.triggerAsync(.load)
        #expect(reopened.uiState.suggestionChip == nil,
                "once-until-changed: the same displayed proposal stays gone")
        #expect(reopenedTelemetry.shownCount == 0)
    }

    @Test("dismissed then manually matched resolves to matched - the save-time state wins")
    func dismissedThenMatched() async {
        let (vm, _, telemetry, _) = makeSuggestionEditorVM(stats: richGlobalStats())
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.selectDateOption("tomorrow"))
        await vm.triggerAsync(.titleChanged("Water the plants"))
        await vm.triggerAsync(.suggestionDismissed)

        await vm.triggerAsync(.timeTapped)
        let manual = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: vm.uiState.date)!
        await vm.triggerAsync(.timeChanged(manual))
        await vm.triggerAsync(.saveTapped)
        #expect(telemetry.outcomes.map(\.2) == [.matched])
    }

    @Test("cancel records no outcome - an abandoned session is not evidence")
    func cancelIsNoOutcome() async {
        let (vm, _, telemetry, _) = makeSuggestionEditorVM(stats: richGlobalStats())
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.selectDateOption("tomorrow"))
        #expect(vm.uiState.suggestionChip != nil)
        // The sheet is simply closed - no save action ever fires.
        #expect(telemetry.outcomes.isEmpty)
    }

    @Test("tapped then adjusted classifies as adjusted")
    func adjustedFlow() async {
        let (vm, _, telemetry, _) = makeSuggestionEditorVM(stats: richGlobalStats())
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.selectDateOption("tomorrow"))
        await vm.triggerAsync(.titleChanged("Water the plants"))
        await vm.triggerAsync(.suggestionTapped)
        await vm.triggerAsync(.timeTapped)
        let manual = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: vm.uiState.date)!
        await vm.triggerAsync(.timeChanged(manual))
        await vm.triggerAsync(.saveTapped)
        #expect(telemetry.outcomes.map(\.2) == [.adjusted])
    }
}

// MARK: - Re-time trigger

@Suite("TaskEditor · suggestions · re-time")
@MainActor
struct TaskEditorReTimeSuggestionTests {

    private func nineAMTomorrow() -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))!
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
    }

    @Test("a series done nightly at 20:00 but scheduled 09:00 offers the due-time change")
    func reTimeFires() async {
        let task = makeTask(
            id: "series-head", title: "Journal", dueAt: nineAMTomorrow(), hasTime: true,
            repeatRule: .daily
        )
        let (vm, repo, telemetry, _) = makeSuggestionEditorVM(
            editing: task, stats: seriesStats(seriesId: "series-head")
        )
        await vm.triggerAsync(.load)
        let chip = try! #require(vm.uiState.suggestionChip)
        #expect(chip.label.contains("8:00"))
        #expect(chip.reason.contains("due time"), "consent names the real semantics")

        await vm.triggerAsync(.suggestionTapped)
        await vm.triggerAsync(.saveTapped)
        // A rule-preserving edit asks for scope; the series branch saves.
        await vm.triggerAsync(.confirmSaveSeries)
        let updated = try! #require(repo.updatedTasks.first)
        let minute = calendar.component(.hour, from: updated.dueAt!) * 60
            + calendar.component(.minute, from: updated.dueAt!)
        #expect(minute == 1200)
        #expect(telemetry.outcomes.map(\.2) == [.accepted])
        #expect(telemetry.outcomes.map(\.0) == [.reTime])
    }

    @Test("one hour of drift is not a scheduling problem - no chip")
    func closeScheduleIsSilent() async {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))!
        let sevenPM = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: tomorrow)!
        let task = makeTask(
            id: "series-head", title: "Journal", dueAt: sevenPM, hasTime: true, repeatRule: .daily
        )
        let (vm, _, _, _) = makeSuggestionEditorVM(
            editing: task, stats: seriesStats(seriesId: "series-head")
        )
        await vm.triggerAsync(.load)
        #expect(vm.uiState.suggestionChip == nil)
    }

    @Test("a one-off far from its completions gets no re-time - no future series to change")
    func oneOffNoReTime() async {
        let task = makeTask(
            id: "solo", title: "Call the bank", dueAt: nineAMTomorrow(), hasTime: true
        )
        // Even with a rich same-id history, no repeat rule means no offer.
        let stats = (0..<8).map { index in
            makeStat(
                taskId: "solo", localDate: liveDay(-1 - index), localMinute: 1200,
                completedAt: Date.now.addingTimeInterval(TimeInterval(-(1 + index)) * 86_400),
                hasTime: true
            )
        }
        let (vm, _, telemetry, _) = makeSuggestionEditorVM(editing: task, stats: stats)
        await vm.triggerAsync(.load)
        #expect(vm.uiState.suggestionChip == nil)
        #expect(telemetry.shownCount == 0)
    }

    @Test("clearing the time retires re-time and lets new-time present - each gets its outcome")
    func triggerHandoff() async {
        let task = makeTask(
            id: "series-head", title: "Journal", dueAt: nineAMTomorrow(), hasTime: true,
            repeatRule: .daily
        )
        // The series history ALSO dominates the global distribution, so
        // new-time has evidence to speak from after the clear.
        let stats = seriesStats(seriesId: "series-head")
            + Array(richGlobalStats(minute: 1200).prefix(12))
        let (vm, _, telemetry, _) = makeSuggestionEditorVM(editing: task, stats: stats)
        await vm.triggerAsync(.load)
        #expect(vm.uiState.suggestionChip != nil)

        await vm.triggerAsync(.clearTimeTapped)
        let chip = vm.uiState.suggestionChip
        #expect(chip != nil, "new-time presents once the time is gone")
        #expect(chip?.label.contains("suggests") == true)
        #expect(telemetry.shownCount == 2, "one presentation per trigger, two triggers")

        await vm.triggerAsync(.saveTapped)
        await vm.triggerAsync(.confirmSaveSeries)
        let outcomes = telemetry.outcomes
        #expect(outcomes.count == 2, "each presented trigger classifies at save")
        #expect(Set(outcomes.map(\.0)) == Set([.newTime, .reTime]))
    }
}
