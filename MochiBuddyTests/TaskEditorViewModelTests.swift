//
//  TaskEditorViewModelTests.swift
//  MochiBuddyTests
//
//  The add/edit sheet: capture defaults, when-field mechanics, and the
//  save / snooze / delete side effects.
//

import Foundation
import Testing
@testable import MochiBuddy

@MainActor
private func makeEditorVM(
    editing: TaskItem? = nil,
    lists: [TaskList] = []
) -> (TaskEditorViewModel, StubTaskRepository) {
    let taskRepo = StubTaskRepository()
    let listRepo = StubListRepository()
    listRepo.lists = lists
    let vm = TaskEditorViewModel(
        editingTask: editing,
        authRepository: StubAuthRepository(),
        taskRepository: taskRepo,
        listRepository: listRepo
    )
    return (vm, taskRepo)
}

private let calendar = Calendar.current

@Suite("TaskEditor · new task")
@MainActor
struct TaskEditorNewTests {

    @Test("fast-capture defaults: due today date-only, medium, inbox, no repeat, can't save yet")
    func defaults() async {
        let (vm, _) = makeEditorVM()
        await vm.triggerAsync(.load)
        #expect(vm.uiState.isEditing == false)
        #expect(vm.uiState.canSave == false)
        #expect(vm.uiState.hasDate == true)
        #expect(vm.uiState.selectedDateId == "today")
        #expect(vm.uiState.hasTime == false)
        #expect(vm.uiState.timeText == "Add time")
        #expect(vm.uiState.selectedPriorityId == "med")
        #expect(vm.uiState.selectedListId == "inbox")
        #expect(vm.uiState.selectedRepeatId == "none")
        #expect(vm.uiState.repeatDayOptions.isEmpty)
        #expect(vm.uiState.overdueBanner == nil)
    }

    @Test("a seeded draft title prefills the field and enables save")
    func draftTitleSeed() async {
        let taskRepo = StubTaskRepository()
        let vm = TaskEditorViewModel(
            editingTask: nil,
            draftTitle: "Plan the trip",
            authRepository: StubAuthRepository(),
            taskRepository: taskRepo,
            listRepository: StubListRepository()
        )
        #expect(vm.uiState.title == "Plan the trip")
        #expect(vm.uiState.canSave == true)
        #expect(vm.uiState.isEditing == false)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.saveTapped)
        #expect(taskRepo.addedDrafts.first?.title == "Plan the trip")
    }

    @Test("a real title enables save; whitespace doesn't")
    func canSave() async {
        let (vm, _) = makeEditorVM()
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.titleChanged("   "))
        #expect(vm.uiState.canSave == false)
        await vm.triggerAsync(.titleChanged("Send invoice"))
        #expect(vm.uiState.canSave == true)
    }

    @Test("saving a new task writes the full draft")
    func saveDraft() async {
        let lists = [TaskList(id: "work", name: "Work", colorHex: "#FF9DC4", icon: "briefcase.fill", order: 0)]
        let (vm, repo) = makeEditorVM(lists: lists)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.titleChanged("  Send invoice  "))
        await vm.triggerAsync(.selectPriority("high"))
        await vm.triggerAsync(.selectList("work"))
        await vm.triggerAsync(.selectRepeat("weekly"))
        await vm.triggerAsync(.notesChanged("Loop in Priya"))
        await vm.triggerAsync(.saveTapped)

        let draft = try! #require(repo.addedDrafts.first)
        #expect(draft.title == "Send invoice", "title must be trimmed")
        #expect(draft.priority == .high)
        #expect(draft.listId == "work")
        #expect(draft.repeatRule == .weekly)
        #expect(draft.notes == "Loop in Priya")
        #expect(draft.dueAt == calendar.startOfDay(for: .now))
        #expect(repo.updatedTasks.isEmpty)
    }

    @Test("saving without a title is refused")
    func saveRefusedEmpty() async {
        let (vm, repo) = makeEditorVM()
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.saveTapped)
        #expect(repo.addedDrafts.isEmpty)
    }

    @Test("selecting Inbox stores nil listId (Inbox is the absence of a list)")
    func inboxIsNil() async {
        let (vm, repo) = makeEditorVM()
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.titleChanged("T"))
        await vm.triggerAsync(.selectList("inbox"))
        await vm.triggerAsync(.saveTapped)
        #expect(repo.addedDrafts.first?.listId == nil)
    }
}

@Suite("TaskEditor · when field")
@MainActor
struct TaskEditorWhenTests {

    @Test("'No date' clears both date and time")
    func noDateClears() async {
        let (vm, repo) = makeEditorVM()
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.titleChanged("T"))
        await vm.triggerAsync(.selectDateOption("noDate"))
        #expect(vm.uiState.hasDate == false)
        #expect(vm.uiState.hasTime == false)
        #expect(vm.uiState.selectedDateId == "noDate")
        await vm.triggerAsync(.saveTapped)
        #expect(repo.addedDrafts.first?.dueAt == nil)
    }

    @Test("a stray picker echo after 'No date' can't resurrect the date")
    func noDateSurvivesPickerEcho() async {
        // Regression: the dismissing wheel used to echo a value change that
        // re-set dueAt to "now", shifting the saved time by a few minutes.
        let (vm, repo) = makeEditorVM()
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.titleChanged("T"))
        await vm.triggerAsync(.timeTapped)
        await vm.triggerAsync(.selectDateOption("noDate"))
        await vm.triggerAsync(.timeChanged(.now))
        await vm.triggerAsync(.dateChanged(.now))
        #expect(vm.uiState.hasDate == false)
        #expect(vm.uiState.hasTime == false)
        await vm.triggerAsync(.saveTapped)
        #expect(repo.addedDrafts.first?.dueAt == nil)
        #expect(repo.addedDrafts.first?.hasTime == false)
    }

    @Test("Tomorrow chip moves the day and keeps a chosen time")
    func tomorrowKeepsTime() async {
        let (vm, repo) = makeEditorVM()
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.titleChanged("T"))
        await vm.triggerAsync(.timeTapped)
        let fivePm = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: .now)!
        await vm.triggerAsync(.timeChanged(fivePm))
        await vm.triggerAsync(.selectDateOption("tomorrow"))
        #expect(vm.uiState.selectedDateId == "tomorrow")
        await vm.triggerAsync(.saveTapped)

        let dueAt = try! #require(repo.addedDrafts.first?.dueAt)
        #expect(calendar.component(.hour, from: dueAt) == 17)
        #expect(calendar.isDateInTomorrow(dueAt))
    }

    @Test("adding a time defaults to the next round hour and sets hasTime")
    func addTime() async {
        let (vm, _) = makeEditorVM()
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.timeTapped)
        #expect(vm.uiState.hasTime == true)
        #expect(vm.uiState.activePicker == .time)
        #expect(vm.uiState.timeText != "Add time")
    }

    @Test("clearing the time keeps the day, date-only")
    func clearTime() async {
        let (vm, repo) = makeEditorVM()
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.titleChanged("T"))
        await vm.triggerAsync(.timeTapped)
        await vm.triggerAsync(.clearTimeTapped)
        #expect(vm.uiState.hasTime == false)
        #expect(vm.uiState.hasDate == true)
        await vm.triggerAsync(.saveTapped)
        #expect(repo.addedDrafts.first?.dueAt == calendar.startOfDay(for: .now))
        #expect(repo.addedDrafts.first?.hasTime == false)
    }

    @Test("changing the date keeps the chosen time of day")
    func dateKeepsTime() async {
        let (vm, repo) = makeEditorVM()
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.titleChanged("T"))
        await vm.triggerAsync(.timeTapped)
        let fivePm = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: .now)!
        await vm.triggerAsync(.timeChanged(fivePm))
        await vm.triggerAsync(.selectDateOption("pick"))
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: .now)!
        await vm.triggerAsync(.dateChanged(nextWeek))
        await vm.triggerAsync(.saveTapped)

        let dueAt = try! #require(repo.addedDrafts.first?.dueAt)
        #expect(calendar.component(.hour, from: dueAt) == 17)
        #expect(calendar.isDate(dueAt, inSameDayAs: nextWeek))
        #expect(repo.addedDrafts.first?.hasTime == true)
    }

    @Test("changing the date without a time stays date-only at start of day")
    func dateOnlyStartOfDay() async {
        let (vm, repo) = makeEditorVM()
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.titleChanged("T"))
        await vm.triggerAsync(.selectDateOption("pick"))
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: .now)!
        await vm.triggerAsync(.dateChanged(nextWeek))
        await vm.triggerAsync(.saveTapped)
        #expect(repo.addedDrafts.first?.dueAt == calendar.startOfDay(for: nextWeek))
        #expect(repo.addedDrafts.first?.hasTime == false)
    }

    @Test("the pick chip toggles the calendar open and closed")
    func pickerToggles() async {
        let (vm, _) = makeEditorVM()
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.selectDateOption("pick"))
        #expect(vm.uiState.activePicker == .date)
        await vm.triggerAsync(.selectDateOption("pick"))
        #expect(vm.uiState.activePicker == TaskEditorBehavior.PickerTarget.none)
    }
}

@Suite("TaskEditor · custom repeat")
@MainActor
struct TaskEditorRepeatTests {

    @Test("selecting Custom seeds the due date's weekday and shows the day row")
    func customSeedsDueWeekday() async {
        let (vm, repo) = makeEditorVM()
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.titleChanged("T"))
        await vm.triggerAsync(.selectRepeat("custom"))
        #expect(vm.uiState.selectedRepeatId == "custom")
        #expect(vm.uiState.repeatDayOptions.count == 7)
        #expect(vm.uiState.repeatDayOptions.filter(\.isOn).map(\.id)
            == [Calendar.current.component(.weekday, from: .now)])

        await vm.triggerAsync(.saveTapped)
        #expect(repo.addedDrafts.first?.repeatRule?.customDays
            == [Calendar.current.component(.weekday, from: .now)])
    }

    @Test("toggling days updates the rule; the last day can't be removed")
    func toggleDays() async {
        let (vm, repo) = makeEditorVM()
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.titleChanged("T"))
        await vm.triggerAsync(.selectRepeat("custom"))
        let seeded = Calendar.current.component(.weekday, from: .now)
        let other = seeded == 2 ? 6 : 2

        await vm.triggerAsync(.toggleRepeatDay(other))
        #expect(vm.uiState.repeatDayOptions.filter(\.isOn).count == 2)

        await vm.triggerAsync(.toggleRepeatDay(seeded))
        // Removing the last remaining day is refused.
        await vm.triggerAsync(.toggleRepeatDay(other))
        #expect(vm.uiState.repeatDayOptions.filter(\.isOn).map(\.id) == [other])

        await vm.triggerAsync(.saveTapped)
        #expect(repo.addedDrafts.first?.repeatRule == .custom([other]))
    }

    @Test("switching from custom to a preset drops the day row")
    func backToPreset() async {
        let (vm, repo) = makeEditorVM()
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.titleChanged("T"))
        await vm.triggerAsync(.selectRepeat("custom"))
        await vm.triggerAsync(.selectRepeat("weekly"))
        #expect(vm.uiState.selectedRepeatId == "weekly")
        #expect(vm.uiState.repeatDayOptions.isEmpty)
        await vm.triggerAsync(.saveTapped)
        #expect(repo.addedDrafts.first?.repeatRule == .weekly)
    }

    @Test("editing a task with a custom rule preselects its days")
    func editPrefillsCustom() async {
        let task = makeTask(id: "t1", title: "Gym", dueAt: Dates.now, repeatRule: .custom([2, 4, 6]))
        let (vm, _) = makeEditorVM(editing: task)
        await vm.triggerAsync(.load)
        #expect(vm.uiState.selectedRepeatId == "custom")
        #expect(vm.uiState.repeatDayOptions.filter(\.isOn).map(\.id).sorted() == [2, 4, 6])
    }
}

@Suite("TaskEditor · edit mode")
@MainActor
struct TaskEditorEditTests {

    private var overdueTask: TaskItem {
        makeTask(
            id: "t1",
            title: "Reply to Sam's email",
            notes: "Loop in Priya on the timeline",
            dueAt: Date.now.addingTimeInterval(-2 * 24 * 3600),
            hasTime: true,
            priority: .high,
            listId: "work"
        )
    }

    @Test("isEditing is true before .load runs - the focus check reads it synchronously")
    func isEditingSetAtInit() async {
        let (editVM, _) = makeEditorVM(editing: overdueTask)
        #expect(editVM.uiState.isEditing == true, "must not wait for .load - the View decides keyboard focus in onLoad")
        #expect(editVM.uiState.title == "Reply to Sam's email")
        #expect(editVM.uiState.canSave == true)

        let (newVM, _) = makeEditorVM()
        #expect(newVM.uiState.isEditing == false)
        #expect(newVM.uiState.canSave == false)
    }

    @Test("edit mode prefills every field and shows the overdue banner")
    func prefills() async {
        let (vm, _) = makeEditorVM(editing: overdueTask)
        await vm.triggerAsync(.load)
        #expect(vm.uiState.isEditing == true)
        #expect(vm.uiState.title == "Reply to Sam's email")
        #expect(vm.uiState.canSave == true)
        #expect(vm.uiState.selectedPriorityId == "high")
        #expect(vm.uiState.selectedListId == "work")
        #expect(vm.uiState.notes == "Loop in Priya on the timeline")
        #expect(vm.uiState.hasTime == true)
        let banner = try! #require(vm.uiState.overdueBanner)
        #expect(banner.contains("2 days"))
    }

    @Test("a future task shows no overdue banner")
    func noBannerWhenOnTime() async {
        let future = makeTask(dueAt: Date.now.addingTimeInterval(3600), hasTime: true)
        let (vm, _) = makeEditorVM(editing: future)
        await vm.triggerAsync(.load)
        #expect(vm.uiState.overdueBanner == nil)
    }

    @Test("saving an edit updates in place - never creates a duplicate")
    func saveUpdates() async {
        let (vm, repo) = makeEditorVM(editing: overdueTask)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.titleChanged("Reply to Sam"))
        await vm.triggerAsync(.selectPriority("low"))
        await vm.triggerAsync(.saveTapped)

        #expect(repo.addedDrafts.isEmpty)
        let updated = try! #require(repo.updatedTasks.first)
        #expect(updated.id == "t1")
        #expect(updated.title == "Reply to Sam")
        #expect(updated.priority == .low)
        #expect(updated.listId == "work", "untouched fields survive the save")
    }

    @Test("snoozing an overdue task pushes it to tomorrow, not to yesterday+1")
    func snoozeOverdue() async {
        let (vm, repo) = makeEditorVM(editing: overdueTask)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.snoozeTapped)

        let call = try! #require(repo.snoozeCalls.first)
        #expect(call.id == "t1")
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))!
        #expect(call.newDueAt == tomorrow, "snoozing something 2 days late must land in the future")
    }

    @Test("snoozing a future task pushes one day past its due date")
    func snoozeFuture() async {
        let dueAt = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: .now))!
        let future = makeTask(id: "f1", dueAt: dueAt, hasTime: false)
        let (vm, repo) = makeEditorVM(editing: future)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.snoozeTapped)
        let expected = calendar.date(byAdding: .day, value: 1, to: dueAt)!
        #expect(repo.snoozeCalls.first?.newDueAt == expected)
    }

    @Test("delete removes exactly this task")
    func delete() async {
        let (vm, repo) = makeEditorVM(editing: overdueTask)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.deleteTapped)
        #expect(repo.deletedIds == ["t1"])
        #expect(repo.updatedTasks.isEmpty)
    }

    @Test("delete and snooze are impossible for a brand-new task")
    func newTaskCannotDeleteOrSnooze() async {
        let (vm, repo) = makeEditorVM()
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.deleteTapped)
        await vm.triggerAsync(.snoozeTapped)
        #expect(repo.deletedIds.isEmpty)
        #expect(repo.snoozeCalls.isEmpty)
    }
}

@Suite("TaskEditor · effort")
@MainActor
struct TaskEditorEffortTests {

    @Test("a new task defaults to no effort; picking a level stores its nominal minutes")
    func newTaskEffort() async {
        let (vm, repo) = makeEditorVM()
        await vm.triggerAsync(.load)
        #expect(vm.uiState.hasEffort == false)
        #expect(vm.uiState.effortText == "Set effort")
        #expect(vm.uiState.effortOptions.map(\.label) == ["Tiny", "Small", "Medium", "Large"])

        await vm.triggerAsync(.titleChanged("Deep clean"))
        await vm.triggerAsync(.selectEffort("large"))
        #expect(vm.uiState.effortText == "Large")
        await vm.triggerAsync(.saveTapped)
        #expect(repo.addedDrafts.first?.estimatedMinutes == 120)
    }

    @Test("editing prefills the level from stored minutes; Clear deletes them on save")
    func editRoundTrip() async {
        let task = makeTask(id: "t1", title: "Report", estimatedMinutes: 60)
        let (vm, repo) = makeEditorVM(editing: task)
        await vm.triggerAsync(.load)
        #expect(vm.uiState.effortText == "Medium")
        #expect(vm.uiState.hasEffort == true)

        await vm.triggerAsync(.selectEffort(nil))
        #expect(vm.uiState.effortText == "Set effort")
        await vm.triggerAsync(.saveTapped)
        #expect(repo.updatedTasks.first?.estimatedMinutes == nil)
    }

    @Test("a detached occurrence keeps its effort and the continuation inherits the series'")
    func detachKeepsEffort() async {
        let task = makeTask(
            id: "r1", title: "Water", dueAt: calendar.startOfDay(for: .now),
            repeatRule: .daily, estimatedMinutes: 30
        )
        let (vm, repo) = makeEditorVM(editing: task)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.selectEffort("large"))
        await vm.triggerAsync(.saveTapped)
        await vm.triggerAsync(.confirmSaveOccurrence)
        #expect(repo.updatedTasks.first?.estimatedMinutes == 120, "the edited occurrence takes the new size")
        #expect(repo.addedDrafts.first?.estimatedMinutes == 30, "the series continues with its original size")
    }
}

@Suite("TaskEditor · push counting")
@MainActor
struct TaskEditorPushCountingTests {

    @Test("moving an incomplete task's due date to a later day counts a reschedule")
    func laterDayCounts() async {
        let task = makeTask(id: "t1", title: "Pay rent", dueAt: calendar.startOfDay(for: .now))
        let (vm, repo) = makeEditorVM(editing: task)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.selectDateOption("tomorrow"))
        await vm.triggerAsync(.saveTapped)
        #expect(repo.updateRescheduleFlags == [true])
    }

    @Test("moving a due date earlier is not a push")
    func earlierDayDoesNotCount() async {
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: .now))!
        let task = makeTask(id: "t1", title: "Pay rent", dueAt: nextWeek)
        let (vm, repo) = makeEditorVM(editing: task)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.selectDateOption("today"))
        await vm.triggerAsync(.saveTapped)
        #expect(repo.updateRescheduleFlags == [false])
    }

    @Test("re-timing within the same day is not a push")
    func sameDayTimeChangeDoesNotCount() async {
        let task = makeTask(id: "t1", title: "Pay rent", dueAt: calendar.startOfDay(for: .now))
        let (vm, repo) = makeEditorVM(editing: task)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.timeTapped)
        await vm.triggerAsync(.saveTapped)
        #expect(repo.updateRescheduleFlags == [false])
    }

    @Test("adding a date to a dateless task is not a push")
    func addingDateDoesNotCount() async {
        let task = makeTask(id: "t1", title: "Pay rent", dueAt: nil)
        let (vm, repo) = makeEditorVM(editing: task)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.selectDateOption("tomorrow"))
        await vm.triggerAsync(.saveTapped)
        #expect(repo.updateRescheduleFlags == [false])
    }

    @Test("skip-occurrence moves the date later without counting - different intent")
    func skipOccurrenceDoesNotCount() async {
        let task = makeTask(id: "r1", title: "Water", dueAt: calendar.startOfDay(for: .now), repeatRule: .daily)
        let (vm, repo) = makeEditorVM(editing: task)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.deleteTapped)
        await vm.triggerAsync(.confirmSkipOccurrence)
        #expect(repo.updateRescheduleFlags == [false])
    }

    @Test("detaching an occurrence to a later day counts - it is still a user push")
    func detachedLaterDayCounts() async {
        let task = makeTask(id: "r1", title: "Water", dueAt: calendar.startOfDay(for: .now), repeatRule: .daily)
        let (vm, repo) = makeEditorVM(editing: task)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.selectDateOption("tomorrow"))
        await vm.triggerAsync(.saveTapped)
        await vm.triggerAsync(.confirmSaveOccurrence)
        #expect(repo.updateRescheduleFlags == [true])
    }

    @Test("a completed task's date move never counts")
    func completedNeverCounts() {
        let done = makeTask(dueAt: Dates.now, completed: true, completedAt: Dates.now)
        let later = Dates.now.addingTimeInterval(3 * 86_400)
        #expect(TaskEditorViewModel.pushesDueDateLater(done, to: later) == false)
    }
}

@Suite("TaskEditor · recurring scope")
@MainActor
struct TaskEditorRecurringScopeTests {

    private var recurringTask: TaskItem {
        makeTask(
            id: "r1",
            title: "Water the plants",
            dueAt: calendar.startOfDay(for: .now),
            priority: .med,
            repeatRule: .daily
        )
    }

    @Test("saving a recurring edit asks for scope instead of writing")
    func savePromptsForScope() async {
        let (vm, repo) = makeEditorVM(editing: recurringTask)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.titleChanged("Water ALL the plants"))
        await vm.triggerAsync(.saveTapped)
        #expect(vm.uiState.showSaveScopeOptions == true)
        #expect(repo.updatedTasks.isEmpty)
        #expect(repo.addedDrafts.isEmpty)
    }

    @Test("changing the rule itself saves straight through - it IS a series edit")
    func ruleChangeSkipsPrompt() async {
        let (vm, repo) = makeEditorVM(editing: recurringTask)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.selectRepeat("weekly"))
        await vm.triggerAsync(.saveTapped)
        #expect(vm.uiState.showSaveScopeOptions == false)
        #expect(repo.updatedTasks.first?.repeatRule == .weekly)
    }

    @Test("series scope updates the document in place, rule intact")
    func saveSeries() async {
        let (vm, repo) = makeEditorVM(editing: recurringTask)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.titleChanged("Water ALL the plants"))
        await vm.triggerAsync(.saveTapped)
        await vm.triggerAsync(.confirmSaveSeries)
        let updated = try! #require(repo.updatedTasks.first)
        #expect(updated.title == "Water ALL the plants")
        #expect(updated.repeatRule == .daily)
        #expect(repo.addedDrafts.isEmpty)
    }

    @Test("occurrence scope detaches the edit and spawns the series continuation")
    func saveOccurrence() async {
        let task = recurringTask
        let (vm, repo) = makeEditorVM(editing: task)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.titleChanged("Water plants (moved)"))
        await vm.triggerAsync(.saveTapped)
        await vm.triggerAsync(.confirmSaveOccurrence)

        let detached = try! #require(repo.updatedTasks.first)
        #expect(detached.id == "r1")
        #expect(detached.title == "Water plants (moved)")
        #expect(detached.repeatRule == nil, "the edited occurrence becomes a one-off")

        let continuation = try! #require(repo.addedDrafts.first)
        #expect(continuation.title == "Water the plants", "the series keeps its original details")
        #expect(continuation.repeatRule == .daily)
        let expected = TaskRepeat.daily.nextOccurrence(after: task.dueAt!)
        #expect(continuation.dueAt == expected)
    }

    @Test("deleting a recurring task asks skip-vs-series instead of deleting")
    func deletePromptsForScope() async {
        let (vm, repo) = makeEditorVM(editing: recurringTask)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.deleteTapped)
        #expect(vm.uiState.showDeleteOptions == true)
        #expect(repo.deletedIds.isEmpty)
    }

    @Test("skip this occurrence re-stamps the due date to the next one")
    func skipOccurrence() async {
        let task = recurringTask
        let (vm, repo) = makeEditorVM(editing: task)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.deleteTapped)
        await vm.triggerAsync(.confirmSkipOccurrence)
        let skipped = try! #require(repo.updatedTasks.first)
        #expect(skipped.dueAt == TaskRepeat.daily.nextOccurrence(after: task.dueAt!))
        #expect(skipped.repeatRule == .daily)
        #expect(repo.deletedIds.isEmpty)
    }

    @Test("delete the series removes the document")
    func deleteSeries() async {
        let (vm, repo) = makeEditorVM(editing: recurringTask)
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.deleteTapped)
        await vm.triggerAsync(.confirmDeleteSeries)
        #expect(repo.deletedIds == ["r1"])
    }
}
