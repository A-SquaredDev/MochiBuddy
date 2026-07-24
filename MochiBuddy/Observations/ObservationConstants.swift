//
//  ObservationConstants.swift
//  MochiBuddy
//
//  Every threshold the observation engine gates on (Personal Layer,
//  Feature 4). Remote-tunable via RemoteTuning, set once at launch;
//  threshold changes re-evaluate deterministically on the next
//  computation - stability is replayed, never stored - so no ledger
//  intervention is ever needed for ordinary tuning.
//
//  When unsure, say nothing: every value here exists to buy silence over
//  a hedged guess. These look like statistics; they are brand protection.
//

import Foundation

enum ObservationConstants {
    /// The evidence window, in days. 42 days is six OPPORTUNITIES per
    /// weekday, not six guaranteed samples - which is exactly why the
    /// spread gates exist.
    static var windowDays = 42
    /// Fixed replay depth for deterministic hysteresis - part of the
    /// algorithm's definition (devices must fold from the same start).
    static var replayDays = 90
    /// One calendar day contributes at most this many completions to any
    /// distribution - a single bulk-cleanup burst cannot mint a trait.
    static var dayCap = 3

    // Productive weekday (one-off completions only - the circularity trap)
    static var weekdayMin = 15
    static var weekdayWeeks = 3
    static var weekdayShare = 0.30

    // Productive time of day (all completions - WHEN in the day the user
    // acts is genuine behavior even for scheduled tasks)
    static var timeOfDayMin = 20
    static var timeOfDayDates = 5
    static var timeOfDayWeeks = 3
    static var timeOfDayShare = 0.40

    /// Top must beat the runner-up by this ratio (weekday + time of day).
    /// Ties are exactly the "when unsure" case.
    static var marginRatio = 1.5

    // Momentum (a current-window fact, never a trait; rising only)
    static var trendHalfMin = 10
    static var trendRatio = 1.3
    /// A relative jump between two tiny rates is not a trend.
    static var trendMinDelta = 0.2
    static var trendCooldownDays = 7

    // List return (an event, fired only AFTER action)
    static var returnQuietDays = 14
    static var returnHistoryMin = 5

    // Comeback pattern
    static var comebackMin = 8
    static var comebackDates = 3
    static var comebackTasks = 3
    static var comebackHours = 24.0
    /// The p75 gate stops three fast saves from hiding two week-long stalls.
    static var comebackP75Hours = 48.0

    /// Hysteresis: consecutive daily snapshots to become, replace, or
    /// retire an incumbent.
    static var stickyDays = 14
    static var rundownWeeklyCap = 2

    /// Bumped ONLY on semantic algorithm changes (band boundaries, type
    /// meaning, replay convention) - clears surfacing cadence state.
    /// Ordinary threshold tuning never touches it.
    static let algorithmVersion = 1
}
