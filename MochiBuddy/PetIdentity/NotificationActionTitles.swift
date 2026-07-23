//
//  NotificationActionTitles.swift
//  MochiBuddy
//
//  UNNotificationAction has a single title and no separate accessibility
//  label, so compact surfaces get a budget rule instead of truncation:
//  include the pet name only while the composed title stays compact
//  (verb + ~12 characters); otherwise fall back to the verb-only label.
//  Sixteen graphemes of CJK or emoji render far wider than 16 Latin
//  characters, so width is estimated, not counted.
//

import Foundation

enum NotificationActionTitles {

    /// Estimated character budget for the name portion of an action title.
    static let compactBudget = 12

    /// "Pet Nori", or "Pet" when the name blows the compact budget.
    static func pet(petName: String) -> String {
        fitsCompactBudget(petName) ? "Pet \(petName)" : "Pet"
    }

    /// "Nori, shh · 24h", or "Shh · 24h" when the name blows the budget.
    /// The valve's length is remote-tunable - the label must never promise
    /// a different duration than it delivers.
    static func shh(petName: String, hours: Int) -> String {
        fitsCompactBudget(petName) ? "\(petName), shh · \(hours)h" : "Shh · \(hours)h"
    }

    static func fitsCompactBudget(_ name: String) -> Bool {
        estimatedWidth(of: name) <= compactBudget
    }

    /// Grapheme count with wide graphemes (CJK, emoji) weighted double -
    /// a render-width estimate, not typography.
    static func estimatedWidth(of name: String) -> Int {
        name.reduce(0) { $0 + (isWide($1) ? 2 : 1) }
    }

    private static func isWide(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        if character.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) {
            return true
        }
        switch scalar.value {
        case 0x1100...0x115F,   // Hangul Jamo
             0x2E80...0x303E,   // CJK radicals, punctuation
             0x3041...0x33FF,   // Hiragana, Katakana, CJK compat
             0x3400...0x4DBF,   // CJK ext A
             0x4E00...0x9FFF,   // CJK unified
             0xA000...0xA4CF,   // Yi
             0xAC00...0xD7A3,   // Hangul syllables
             0xF900...0xFAFF,   // CJK compat ideographs
             0xFE30...0xFE4F,   // CJK compat forms
             0xFF00...0xFF60,   // fullwidth forms
             0xFFE0...0xFFE6,
             0x20000...0x2FFFD,
             0x30000...0x3FFFD:
            return true
        default:
            return false
        }
    }
}
