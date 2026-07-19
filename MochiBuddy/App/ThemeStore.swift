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
    /// Pushes the flavor's alternate-icon name to the system (nil name =
    /// primary AppIcon). Wired to UIApplication by AppContainer; nil in
    /// unit tests so ThemeStore stays UIKit-free.
    private let syncAppIcon: ((String?) -> Void)?

    init(defaults: UserDefaults = .standard, syncAppIcon: ((String?) -> Void)? = nil) {
        self.defaults = defaults
        self.syncAppIcon = syncAppIcon
        let savedId = defaults.string(forKey: Self.defaultsKey)
        // Black Sesame is the launch default flavor.
        current = MochiTheme.theme(id: savedId ?? MochiTheme.sesame.id)
        // Re-align after reinstalls: the saved flavor survives in defaults
        // but the home-screen icon resets to primary.
        syncAppIcon?(Self.alternateIconName(for: current.id))
    }

    func apply(themeId: String) {
        current = MochiTheme.theme(id: themeId)
        defaults.set(themeId, forKey: Self.defaultsKey)
        syncAppIcon?(Self.alternateIconName(for: themeId))
    }

    /// "AppIcon-<flavor>" for the light flavors; nil for Black Sesame,
    /// whose art is the primary AppIcon.
    static func alternateIconName(for themeId: String) -> String? {
        themeId == MochiTheme.sesame.id ? nil : "AppIcon-\(themeId)"
    }
}
