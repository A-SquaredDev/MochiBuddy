//
//  TaperTracker.swift
//  MochiBuddy
//
//  The floor-taper state machine (design doc: Cadence constants). Volume
//  escalates with depth but decays with duration: day 1 at the floor is a
//  bad day, day 7 is burnout. The counter advances per calendar day spent
//  at the floor and resets ONLY on a genuine recovery: climbing to a good
//  band and holding it. A momentary blip (one task done, mood pops up,
//  slides back overnight) must never reset it - that would hand the
//  person who managed one task MORE pings than doing nothing.
//

import Foundation

struct TaperState: Codable, Equatable {
    /// First calendar day of the current consecutive floor stretch.
    var firstFloorDay: Date?
    /// Most recent calendar day the floor was observed.
    var lastFloorDay: Date?
    /// When the mood climbed to content-or-better and stayed there since.
    var goodSince: Date?

    /// Completed consecutive days at the floor before `today` - the
    /// planner's taper input (0 = today is day 1).
    func consecutiveFloorDays(before today: Date, calendar: Calendar = .current) -> Int {
        guard let first = firstFloorDay else { return 0 }
        let start = calendar.startOfDay(for: first)
        let now = calendar.startOfDay(for: today)
        return max(0, calendar.dateComponents([.day], from: start, to: now).day ?? 0)
    }
}

enum TaperTracker {

    /// A recovery only counts once a good band has held this long.
    static let recoveryHold: TimeInterval = 24 * 3600

    /// Fold one observation of the current band into the state. Called on
    /// every re-lay - deterministic, so it's fully unit-testable.
    static func update(
        _ state: TaperState,
        band: MoodBand,
        now: Date,
        calendar: Calendar = .current
    ) -> TaperState {
        var next = state
        let today = calendar.startOfDay(for: now)

        if band == .verySad {
            // Unobserved gaps between floor sightings mean no user action
            // happened (mood only rises on action, and every action
            // re-lays), so the floor persisted through them - the stretch
            // carries. Only a held recovery below ever clears it.
            next.firstFloorDay = state.firstFloorDay ?? today
            next.lastFloorDay = today
            next.goodSince = nil
            return next
        }

        if band >= .content {
            let goodSince = state.goodSince ?? now
            next.goodSince = goodSince
            // Held long enough: genuine recovery, the slate clears.
            if now.timeIntervalSince(goodSince) >= recoveryHold {
                next.firstFloorDay = nil
                next.lastFloorDay = nil
            }
        } else {
            // uneasy/anxious: the floor stretch carries, and any recovery
            // clock is interrupted - a blip up that slid back never counts.
            next.goodSince = nil
        }
        return next
    }
}
