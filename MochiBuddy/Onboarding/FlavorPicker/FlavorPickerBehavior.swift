//
//  FlavorPickerBehavior.swift
//  MochiBuddy
//

import SwiftUI

enum FlavorPickerBehavior {

    /// Display-ready swatch colors for one flavor.
    struct FlavorUIItem: Equatable, Identifiable {
        let id: String
        let name: String
        let bg: Color
        let primary: Color
        let pet: Color
        let ink: Color
    }

    struct UIState: UpdatableStruct, Equatable {
        var flavors: [FlavorUIItem] = []
        var selectedId = ""
    }

    enum ViewAction {
        case load
        case select(String)
        case continueTapped
    }

    enum NavigationEvent {
        case next
    }
}
