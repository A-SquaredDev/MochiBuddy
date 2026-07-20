//
//  MoodBand.swift
//  MochiBuddy
//
//  The six mood states from the design doc's mood algorithm, keyed by the
//  0-100 value. This is the notification scheduler's vocabulary (cadence
//  is per band); the visual MochiMood keeps its own coarser bands.
//

import Foundation

enum MoodBand: Int, CaseIterable, Comparable, Equatable {
    case verySad
    case anxious
    case uneasy
    case content
    case happy
    case ecstatic

    /// Bands (design doc): very sad 0-15 · anxious 15-35 · uneasy 35-50 ·
    /// content 50-70 · happy 70-88 · ecstatic 88-100.
    init(value: Double) {
        switch value {
        case ..<15: self = .verySad
        case ..<35: self = .anxious
        case ..<50: self = .uneasy
        case ..<70: self = .content
        case ..<88: self = .happy
        default: self = .ecstatic
        }
    }

    /// The value where this band begins (inclusive).
    var lowerBound: Double {
        switch self {
        case .verySad: 0
        case .anxious: 15
        case .uneasy: 35
        case .content: 50
        case .happy: 70
        case .ecstatic: 88
        }
    }

    static func < (lhs: MoodBand, rhs: MoodBand) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
