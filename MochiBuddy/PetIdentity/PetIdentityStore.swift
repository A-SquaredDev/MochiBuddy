//
//  PetIdentityStore.swift
//  MochiBuddy
//
//  App-wide pet identity state (name + adoption date) and the one
//  PetIdentityDidChange pipeline every rename entry point routes through:
//  1. sanitize + persist (skipped entirely when the sanitized value is
//     unchanged - no write, no propagation, no event),
//  2. re-register notification action labels (before any re-lay),
//  3. notification re-lay (mood pings + rundowns rewritten; promises
//     untouched - they contain no name, by the locked rule),
//  4. widget mirror + reload (rides the re-lay's onRelaid hook),
//  5. live UI refresh (observed; screens re-derive on appear).
//  Steps 2-4 are wired by AppContainer through onIdentityChanged so no
//  entry point can forget a surface.
//
//  Injected, never a singleton (same doctrine as ThemeStore).
//

import Foundation
import Observation
import os

enum PetIdentityTelemetryEvent {
    /// Onboarding naming beat completed. `custom` = sanitized name differs
    /// from the default, regardless of which button confirmed it.
    /// NEVER the string - the name is user content and is never logged.
    case petNamed(custom: Bool)
    /// A rename that actually changed the sanitized value. Count only.
    case petRenamed
}

protocol PetIdentityTelemetry: AnyObject {
    func log(_ event: PetIdentityTelemetryEvent)
}

final class OSLogPetIdentityTelemetry: PetIdentityTelemetry {

    private let logger = Logger(subsystem: "com.aaronmckain.MochiBuddy", category: "petIdentity")

    func log(_ event: PetIdentityTelemetryEvent) {
        switch event {
        case .petNamed(let custom):
            logger.info("pet_named custom=\(custom)")
        case .petRenamed:
            logger.info("pet_renamed")
        }
    }
}

@MainActor
@Observable
final class PetIdentityStore {

    private static func migratedKey(for userId: String) -> String {
        // Per-UID namespacing: a sign-out/sign-in on the same device gets
        // its own one-time pass.
        "mochi.petIdentity.migrated.\(userId)"
    }

    private(set) var name: String = PetNameSanitizer.defaultName
    private(set) var adoptedOn: String?

    /// PetIdentityDidChange, step 2 onward. Fired only after a real,
    /// persisted change; AppContainer wires label re-registration and the
    /// re-lay here in order.
    var onIdentityChanged: ((String) -> Void)?
    /// Fired whenever a profile's identity is (re)loaded, so startup can
    /// align action labels with a name chosen on another device or a past
    /// session. Registration is cheap and idempotent.
    var onLoaded: ((String) -> Void)?

    private let profileRepository: UserProfileRepository
    private let telemetry: PetIdentityTelemetry?
    private let defaults: UserDefaults

    init(
        profileRepository: UserProfileRepository,
        telemetry: PetIdentityTelemetry? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.profileRepository = profileRepository
        self.telemetry = telemetry
        self.defaults = defaults
    }

    // MARK: - Load + one-time migration

    /// Adopts the profile's identity and runs the one-time persisted
    /// migration for legacy profiles: missing `mochiName` becomes a
    /// persisted "Mochi"; missing `adoptedOn` is backfilled from
    /// `createdAt` in the device's current timezone and persisted. The
    /// same adoptedOn path doubles as the interrupted-onboarding backstop
    /// (a fresh profile's createdAt is today). Decoder fallbacks cover
    /// only the pre-migration window; after this, the persisted value is
    /// the truth.
    func load(profile: UserProfile, now: Date = .now) async {
        name = profile.mochiName
        adoptedOn = profile.adoptedOn

        let flagKey = Self.migratedKey(for: profile.id)
        if !defaults.bool(forKey: flagKey) {
            // Persist the canonical name once so the decoder fallback is
            // never load-bearing again. Idempotent for migrated profiles.
            try? await profileRepository.saveMochiName(profile.mochiName, userId: profile.id)
            defaults.set(true, forKey: flagKey)
        }
        if adoptedOn == nil {
            await stampAdoption(anchoredTo: profile.createdAt ?? now, userId: profile.id)
        }
        onLoaded?(name)
    }

    // MARK: - Naming (onboarding beat)

    /// The naming beat: sanitize + persist the chosen name and stamp the
    /// write-once adoption date. No pipeline fires - nothing is scheduled
    /// or mirrored yet during onboarding.
    func completeNamingBeat(rawName: String, userId: String, now: Date = .now) async {
        let chosen = PetNameSanitizer.canonicalName(from: rawName)
        name = chosen
        try? await profileRepository.saveMochiName(chosen, userId: userId)
        defaults.set(true, forKey: Self.migratedKey(for: userId))
        await stampAdoption(anchoredTo: now, userId: userId)
        telemetry?.log(.petNamed(custom: chosen != PetNameSanitizer.defaultName))
    }

    // MARK: - Rename (PetIdentityDidChange)

    /// Every rename entry point routes through here. Returns whether the
    /// sanitized value actually changed; a no-op rename does not write,
    /// does not propagate, and does not log.
    @discardableResult
    func rename(to rawName: String, userId: String) async -> Bool {
        let sanitized = PetNameSanitizer.canonicalName(from: rawName)
        guard sanitized != name else { return false }
        name = sanitized
        try? await profileRepository.saveMochiName(sanitized, userId: userId)
        telemetry?.log(.petRenamed)
        onIdentityChanged?(sanitized)
        return true
    }

    private func stampAdoption(anchoredTo date: Date, userId: String) async {
        let stamp = AdoptedOnDate.string(from: date, in: .current)
        try? await profileRepository.stampAdoptedOn(stamp, userId: userId)
        if adoptedOn == nil {
            adoptedOn = stamp
        }
    }
}
