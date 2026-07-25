//
//  CallbackConstants.swift
//  MochiBuddy
//
//  Memory-callback thresholds (Personal Layer, Feature 2). The six vars
//  are remote-tunable via RemoteTuning, set once at launch. The lets are
//  part of the taxonomy's definition (what a recovery IS), not levers.
//
//  There is no repeat cooldown here: once-until-changed replaced it. The
//  milestone set (1 week, 1 month, yearly) is deliberately not tunable
//  either - calendar facts live in AnniversaryCalendar.
//

import Foundation

enum CallbackConstants {
    /// At most this many scheduled callbacks per ISO week.
    static var weeklyCap = 2
    /// Minimum days between scheduled callbacks.
    static var minGapDays = 3
    /// No callbacks before this many days of relationship - no day-3
    /// nostalgia.
    static var minAgeDays = 21
    /// A memory must be old enough to BE one (best day, recovery, and a
    /// still-active streak record). Date echo is date-bound and exempt.
    static var factAgeDays = 7
    /// Best-day floor: completions AND distinct tasks/series that day.
    static var bestDayMin = 5
    /// While the record belongs to the active streak, stay quiet this
    /// long after its milestone celebration - congratulate, don't
    /// immediately "remember".
    static var streakQuietDays = 14

    // Taxonomy definitions, fixed.

    /// A dig-out needs at least this many overdue clears...
    static let recoveryMinClears = 3
    /// ...from distinct tasks/series inside this window...
    static let recoveryWindowHours = 48.0
    /// ...with at least one clear this far past due (three barely-late
    /// tasks don't mint a dig-out).
    static let recoveryMinOverdueHours = 24.0
    /// Streak-era records below this never surface.
    static let streakEraMin = 7
}
