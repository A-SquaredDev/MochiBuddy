//
//  DisplayNamePromptGate.swift
//  MochiBuddy
//
//  Decides whether to ask "What should Mochi call you?" on entering Home.
//
//  Apple shares a display name only on the very first authorization, so an
//  account whose profile document is fresh (a deletion followed by a new
//  sign-in, most often) lands in the app nameless and stays that way until
//  someone finds the pencil on the You tab. The ask is one-time per UID:
//  saving a name closes it structurally (the name is no longer empty), and
//  skipping records a device-local flag. Sibling of NudgeLedger in shape -
//  per-UID UserDefaults, cleared on account deletion.
//

import Foundation

@MainActor
final class DisplayNamePromptGate {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private static func key(for userId: String) -> String {
        "mochi.displayNamePrompt.skipped.\(userId)"
    }

    /// True when the profile has no usable name and this UID has not
    /// already waved the ask away. Takes a real profile on purpose: a
    /// failed fetch must not read as "nameless" and greet a named user.
    func shouldPrompt(profile: UserProfile, userId: String) -> Bool {
        let name = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard name.isEmpty else { return false }
        return !defaults.bool(forKey: Self.key(for: userId))
    }

    func recordSkipped(userId: String) {
        defaults.set(true, forKey: Self.key(for: userId))
    }

    /// Account deletion clears the UID's flag outright.
    func clear(userId: String) {
        defaults.removeObject(forKey: Self.key(for: userId))
    }
}
