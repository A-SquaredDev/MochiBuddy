//
//  PetNameSanitizer.swift
//  MochiBuddy
//
//  Sanitizes the pet name at every persistence boundary (same doctrine as
//  bedtime windows). Any printable characters are allowed - it's their pet;
//  sanitization handles safety and length, never taste.
//

import Foundation

enum PetNameSanitizer {

    /// The brand name doubles as the default pet name by design.
    static let defaultName = "Mochi"

    /// Cap counted in grapheme clusters, cutting only on grapheme boundaries
    /// (an emoji ZWJ sequence or a composed Hangul syllable counts as one).
    static let maxGraphemes = 16

    /// Removes line breaks, C0/C1 controls, and disruptive bidirectional
    /// controls; trims and collapses whitespace; caps at `maxGraphemes`.
    /// ZWJ (U+200D), variation selectors, and combining marks are never
    /// stripped - removing a joiner corrupts a joined emoji into its parts.
    static func sanitize(_ raw: String) -> String {
        // Banned whitespace (tab, LF, CR, NEL, LS, PS) separates words, so
        // it becomes a space for the collapse below rather than vanishing
        // and gluing "Nori\nBell" into "NoriBell". Other banned scalars
        // are removed outright.
        let filtered = String(String.UnicodeScalarView(
            raw.unicodeScalars.compactMap { scalar in
                guard isBanned(scalar) else { return scalar }
                return scalar.properties.isWhitespace ? " " : nil
            }
        ))
        let collapsed = filtered
            .split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return String(collapsed.prefix(maxGraphemes))
    }

    /// Classification for values read from any source: a valid-but-overlong
    /// string sanitizes and caps; a missing value, wrong-type value (decoded
    /// as nil), or string that is empty *after* sanitization becomes the
    /// default. Never broken copy.
    static func canonicalName(from raw: String?) -> String {
        guard let raw else { return defaultName }
        let sanitized = sanitize(raw)
        return sanitized.isEmpty ? defaultName : sanitized
    }

    private static func isBanned(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00...0x1F, 0x7F, 0x80...0x9F:
            return true // C0 controls, DEL, C1 controls (incl. CR/LF/NEL)
        case 0x2028, 0x2029:
            return true // line / paragraph separators
        case 0x202A...0x202E, 0x2066...0x2069:
            return true // bidi embeddings, overrides, isolates
        default:
            return false
        }
    }
}

/// Live-field acceptance rule, kept pure so it is table-testable. The cap
/// counts *committed* graphemes and never interferes with marked
/// (in-composition) text - CJK composition completes first, then the cap
/// applies on commit.
enum PetNameFieldPolicy {
    static func acceptsChange(proposed: String, hasMarkedText: Bool) -> Bool {
        hasMarkedText || proposed.count <= PetNameSanitizer.maxGraphemes
    }
}
