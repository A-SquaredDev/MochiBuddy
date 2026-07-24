//
//  LetterConstants.swift
//  MochiBuddy
//
//  Every threshold the weekly letter gates on (Personal Layer, Feature 3).
//  Remote-tunable via RemoteTuning, set once at launch. Constants land at
//  compose time and are BAKED into the stored letter - a later tuning pass
//  changes future letters only, never a postcard already written.
//

import Foundation

enum LetterConstants {
    /// Calendar weekday of the send day (1 = Sunday).
    static var sendWeekday = 1
    /// Local hour of the effective send time; the bedtime clamp may pull
    /// it earlier, and the clamp moves the CUTOFF (they are one instant).
    static var sendHour = 19
    /// Beats per letter; rough periods cap at 2 regardless.
    static var maxBeats = 3
    /// A period with at most this many completions (and few dues) is
    /// quiet: short, cozy, nothing was wrong.
    static var quietMax = 2
    /// Days-with-overdue-tasks threshold for the rough classification.
    static var roughOverdueDays = 4
    /// Completions vs the trailing average for the great classification.
    static var greatRatio = 1.5

    /// Bumped on semantic composer changes; stored on every letter as
    /// provenance alongside the copy-deck version.
    static let composerVersion = 1
}
