//
//  ManageListsViewModelTests.swift
//  MochiBuddyTests
//
//  Manage lists - creation must update the rows optimistically, never
//  via a re-fetch that can race the fire-and-forget Firestore write.
//

import Foundation
import Testing
@testable import MochiBuddy

@MainActor
private func makeManageListsVM(
    lists: [TaskList] = []
) -> (ManageListsViewModel, StubListRepository) {
    let listRepo = StubListRepository()
    listRepo.lists = lists
    let vm = ManageListsViewModel(
        authRepository: StubAuthRepository(),
        listRepository: listRepo,
        membershipSession: MembershipSession()
    )
    return (vm, listRepo)
}

@Suite("ManageLists · create")
@MainActor
struct ManageListsCreateTests {

    @Test("a created list appears immediately without re-fetching the repo")
    func optimisticCreate() async {
        let (vm, repo) = makeManageListsVM()
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.draftNameChanged("Errands"))
        await vm.triggerAsync(.createTapped)

        #expect(repo.createdNames == ["Errands"])
        #expect(vm.uiState.lists.map(\.name) == ["Errands"],
                "the row must come from the returned list, not a reload - repo.lists was never updated")
        #expect(vm.uiState.draftName.isEmpty)
        #expect(vm.uiState.canCreate == false)
    }

    @Test("creation appends after existing lists")
    func appendsAfterExisting() async {
        let groceries = TaskList(id: "l1", name: "Groceries", colorHex: "#C9A6FF", icon: "tag.fill", order: 0)
        let (vm, _) = makeManageListsVM(lists: [groceries])
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.draftNameChanged("Work"))
        await vm.triggerAsync(.createTapped)
        #expect(vm.uiState.lists.map(\.name) == ["Groceries", "Work"])
    }

    @Test("a post-create echo of the old draft can't resurrect the cleared field")
    func createSwallowsEcho() async {
        let (vm, _) = makeManageListsVM()
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.draftNameChanged("Errands"))
        await vm.triggerAsync(.createTapped)
        await vm.triggerAsync(.draftNameChanged("Errands"))
        #expect(vm.uiState.draftName.isEmpty)
        #expect(vm.uiState.canCreate == false)
        await vm.triggerAsync(.draftNameChanged("Chores"))
        #expect(vm.uiState.draftName == "Chores")
    }

    @Test("whitespace-only names are rejected")
    func rejectsEmptyName() async {
        let (vm, repo) = makeManageListsVM()
        await vm.triggerAsync(.load)
        await vm.triggerAsync(.draftNameChanged("   "))
        await vm.triggerAsync(.createTapped)
        #expect(repo.createdNames.isEmpty)
        #expect(vm.uiState.lists.isEmpty)
    }
}
