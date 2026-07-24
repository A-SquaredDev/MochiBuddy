//
//  LetterArchiveBehavior.swift
//  MochiBuddy
//
//  The letter archive (Personal Layer, Feature 3): the relationship made
//  visible. Owned by the Personal Layer - routed from a temporary
//  "Mochi's letters" row in You; Feature 6 re-routes the same destination
//  from the Journal tab and retires the row.
//

import Foundation

enum LetterArchiveBehavior {

    struct LetterRow: Equatable, Identifiable {
        let id: String
        /// "Week of July 14"
        let title: String
        /// First body line, as the preview.
        let snippet: String
        let isUnread: Bool
    }

    struct UIState: UpdatableStruct, Equatable {
        var isLoading = true
        var petName = "Mochi"
        var rows: [LetterRow] = []
        var showEmptyState = false
    }

    enum ViewAction {
        case load
        case letterTapped(String)
    }

    enum NavigationEvent {
        case openLetter(Letter)
    }
}
