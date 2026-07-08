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
        #expect(vm.uiState.dateText == "Today")
        #expect(vm.uiState.hasTime == false)
        #expect(vm.uiState.timeText == "Add time")
        #expect(vm.uiState.selectedPriorityId == "med")
        #expect(vm.uiState.selectedListId == "inbox")
        #expect(vm.uiState.selectedRepeatId == "none")
        #expect(vm.uiState.overdueBanner == nil)
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
        let lists = [TaskList(id: "work", name: "Work", colorHex: "#FF9DC4", icon: "💼", order: 0)]
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
        await vm.triggerAsync(.noDateTapped)
        #expect(vm.uiState.hasDate == false)
        #expect(vm.uiState.hasTime == false)
        #expect(vm.uiState.dateText == "Add date")
        await vm.triggerAsync(.saveTapped)
        #expect(repo.addedDrafts.first?.dueAt == nil)
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

    @Test("changing the date keeps the chosen time of day")
    func dateKeepsTime() async {
        let (vm, repo) = makeEditorVM()
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.titleChanged("T"))
        let fivePm = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: .now)!
        await vm.triggerAsync(.timeChanged(fivePm))
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
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: .now)!
        await vm.triggerAsync(.dateChanged(nextWeek))
        await vm.triggerAsync(.saveTapped)
        #expect(repo.addedDrafts.first?.dueAt == calendar.startOfDay(for: nextWeek))
        #expect(repo.addedDrafts.first?.hasTime == false)
    }

    @Test("date pill toggles its picker open and closed")
    func pickerToggles() async {
        let (vm, _) = makeEditorVM()
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.dateTapped)
        #expect(vm.uiState.activePicker == .date)
        await vm.triggerAsync(.dateTapped)
        #expect(vm.uiState.activePicker == TaskEditorBehavior.PickerTarget.none)
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

    @Test("saving an edit updates in place — never creates a duplicate")
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
