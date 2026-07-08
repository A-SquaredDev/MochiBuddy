//
//  ComfortBufferStore.swift
//  MochiBuddy
//
//  The comfort buffer — a temporary lift from pets/treats that decays back
//  to the baseline and never moves it. On-device only (design doc): the
//  widget will read this from the App Group later; it needs no cloud sync.
//

import Foundation

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
        return min(MoodEngine.Constants.bufferCap, total)
    }

    private func load() -> [BufferBoost] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([BufferBoost].self, from: data)) ?? []
    }

    private func save(_ boosts: [BufferBoost]) {
        defaults.set(try? JSONEncoder().encode(boosts), forKey: Self.key)
    }
}
