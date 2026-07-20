//
//  ComfortBufferStore.swift
//  MochiBuddy
//
//  The comfort buffer - a temporary lift from pets/treats that decays back
//  to the baseline and never moves it. On-device only (design doc): the
//  widget will read this from the App Group later; it needs no cloud sync.
//

import Foundation

/// The buffer's shared tuning - lives here (not MoodEngine) because the
/// widget extension clamps with it too and never links the engine.
enum MochiComfort {
    static let bufferCap: Double = 30
}

/// One pet or treat: a lift that fades linearly to zero over its duration.
struct BufferBoost: Codable, Equatable {
    let lift: Double
    let startedAt: Date
    let duration: TimeInterval

    func value(at now: Date) -> Double {
        let elapsed = now.timeIntervalSince(startedAt)
        guard elapsed >= 0, elapsed < duration else { return 0 }
        return lift * (1 - elapsed / duration)
    }
}

protocol ComfortBufferStore: AnyObject {
    func add(lift: Double, duration: TimeInterval)
    /// Sum of active boosts, clamped to the buffer cap (+30).
    func currentValue(now: Date) -> Double
    /// When the last active boost fully fades - nil when nothing is active.
    func latestExpiry(now: Date) -> Date?
    /// The live boosts themselves - the forecast simulates their decay.
    func activeBoosts(now: Date) -> [BufferBoost]
}

final class UserDefaultsComfortBufferStore: ComfortBufferStore {

    private static let key = "mochi.comfortBoosts"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func add(lift: Double, duration: TimeInterval) {
        var boosts = load().filter { $0.value(at: .now) > 0 }
        boosts.append(BufferBoost(lift: lift, startedAt: .now, duration: duration))
        save(boosts)
    }

    func currentValue(now: Date) -> Double {
        let total = load().reduce(0) { $0 + $1.value(at: now) }
        return min(MochiComfort.bufferCap, total)
    }

    func latestExpiry(now: Date) -> Date? {
        load()
            .filter { $0.value(at: now) > 0 }
            .map { $0.startedAt.addingTimeInterval($0.duration) }
            .max()
    }

    func activeBoosts(now: Date) -> [BufferBoost] {
        load().filter { $0.value(at: now) > 0 }
    }

    /// One-time move of boosts from the app's standard defaults into the
    /// App Group, so the widget sees the same buffer (design doc: the
    /// buffer lives in App Group shared storage; still device-local).
    static func migrateToAppGroup(
        from old: UserDefaults = .standard,
        to group: UserDefaults
    ) {
        guard group.data(forKey: key) == nil,
              let legacy = old.data(forKey: key)
        else { return }
        group.set(legacy, forKey: key)
        old.removeObject(forKey: key)
    }

    private func load() -> [BufferBoost] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([BufferBoost].self, from: data)) ?? []
    }

    private func save(_ boosts: [BufferBoost]) {
        defaults.set(try? JSONEncoder().encode(boosts), forKey: Self.key)
    }
}
