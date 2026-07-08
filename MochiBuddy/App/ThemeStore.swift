//
//  ThemeStore.swift
//  MochiBuddy
//
//  App-wide flavor state. Injected (never a singleton); RootView observes it
//  and feeds the theme into the environment so a flavor change recolors
//  everything live.
//

import Foundation
import Observation

@MainActor
@Observable
final class ThemeStore {

    private static let defaultsKey = "mochi.themeId"

    private(set) var current: MochiTheme

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedId = defaults.string(forKey: Self.defaultsKey)
        // Black Sesame is the launch default flavor.
        current = MochiTheme.theme(id: savedId ?? MochiTheme.sesame.id)
    }

    func apply(themeId: String) {
        current = MochiTheme.theme(id: themeId)
        defaults.set(themeId, forKey: Self.defaultsKey)
    }
}
