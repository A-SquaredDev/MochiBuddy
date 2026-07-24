//
//  LetterDetailBehavior.swift
//  MochiBuddy
//
//  One letter, read in full (Personal Layer, Feature 3). Everything shown
//  comes from stored snapshots - the postcard never re-renders against
//  live state. Sharing defaults to the private variant; full is per-share
//  opt-in and rough letters never offer it.
//

import Foundation

enum LetterDetailBehavior {

    struct UIState: UpdatableStruct, Equatable {
        var weekTitle = ""
        var dateRangeText = ""
        var bodyText = ""
        var petName = "Mochi"
        /// "With Nori since March" - from the adoption snapshot; empty hides.
        var adoptionLine = ""
        var offersFullShare = true
    }

    enum ViewAction {
        case load
        case sharedTapped(variant: String)
    }
}
