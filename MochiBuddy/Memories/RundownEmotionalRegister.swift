//
//  RundownEmotionalRegister.swift
//  MochiBuddy
//
//  The mood gate for memory callbacks (Personal Layer, Feature 2): the
//  predicted BASELINE at the rundown's fire time, including the
//  projected taper stretch - computed during re-lay from the same
//  forecast the rundown already evaluates at fire time (the
//  RundownRanker precedent).
//
//  Explicitly NOT the current mood at scheduling time, and NOT the
//  buffer-lifted displayed mood: a pet or treat must never temporarily
//  unlock trophy copy for an anxious user, and the comfort buffer is
//  device-local - gating on it would let two devices choose different
//  registers. Baseline task pressure is the stable, synced input, so
//  the register is cross-device deterministic.
//
//  The register gates CALLBACKS only. Anniversary lines ignore it: a
//  date is not a demand.
//

import Foundation

enum RundownEmotionalRegister: String, Equatable {
    /// Content and above: any callback type.
    case open
    /// Uneasy / anxious: recovery only - the one fact that helps while
    /// behind, because it is ABOUT getting out.
    case recoveryOnly
    /// Floor / chronic-taper: none. The taper's pure-presence copy owns
    /// this register; a trophy shelf helps nobody at the floor.
    case closed

    /// Which callback types this register admits.
    func admits(_ type: CallbackType) -> Bool {
        switch self {
        case .open: true
        case .recoveryOnly: type == .recovery
        case .closed: false
        }
    }

    static func evaluate(
        fireAt: Date,
        snapshot: MoodSnapshot,
        taper: TaperState,
        calendar: Calendar
    ) -> RundownEmotionalRegister {
        // Baseline, never displayed: MoodForecast.band(at:) bands the
        // buffer-lifted value and must not be used here.
        let baseline = MoodForecast.baseline(at: fireAt, snapshot: snapshot, calendar: calendar)
        let band = MoodBand(value: baseline)

        if band == .verySad { return .closed }
        if band >= .content { return .open }

        // Uneasy or anxious. Inside a chronic floor stretch (day 3+ and
        // no held recovery yet) a morning blip above the floor is still a
        // chronic-taper day - stay closed, conservatively.
        if taper.firstFloorDay != nil,
           taper.consecutiveFloorDays(before: fireAt, calendar: calendar) >= 2 {
            return .closed
        }
        return .recoveryOnly
    }
}
