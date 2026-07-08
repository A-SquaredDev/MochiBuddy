//
//  MeetMochiViewModel.swift
//  MochiBuddy
//
//  2 · Meet Mochi — the emotional hook: beaming baseline, the downswing,
//  then recovery. Three beats on one screen.
//

import Foundation

final class MeetMochiViewModel: ObservableStateViewModel<
    MeetMochiBehavior.UIState,
    MeetMochiBehavior.ViewAction,
    MeetMochiBehavior.NavigationEvent
> {

    init() {
        super.init(initialState: MeetMochiBehavior.UIState())
    }

    override func triggerAsync(_ action: MeetMochiBehavior.ViewAction) async {
        switch action {
        case .continueTapped:
            let next = uiState.pageIndex + 1
            if next < MeetMochiBehavior.pages.count {
                show(page: next)
            } else {
                setNavigationEvent(.showFirstTask)
            }
        case .backTapped:
            let previous = uiState.pageIndex - 1
            if previous >= 0 {
                show(page: previous)
            }
        }
    }

    private func show(page index: Int) {
        setUIState(
            uiState
                .updating(\.pageIndex, to: index)
                .updating(\.page, to: MeetMochiBehavior.pages[index])
                .updating(\.canGoBack, to: index > 0)
        )
    }
}
