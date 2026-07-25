//
//  SuggestionCopy.swift
//  MochiBuddy
//
//  Chip copy for suggested times (Personal Layer, Feature 5). The reason
//  line takes the proposal's scope TIER, so a global fallback can never
//  be explained as list- or task-specific - provenance is a type, not a
//  string. Copy-style rules apply: no em dashes, no emoji, no
//  percentages, no evidence talk. Re-time copy says what the tap does -
//  it changes the task's DUE TIME going forward, never "the reminder" -
//  and never implies Mochi knows the later time is objectively better.
//

import Foundation

enum SuggestionCopy {

    /// Locale-styled clock time for a canonical minute (UTC-anchored, so
    /// the rendering is a pure function of the minute and locale).
    static func timeText(minute: Int, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(minute * 60)))
    }

    static func chipLabel(
        _ proposal: SuggestionProposal, petName: String, locale: Locale = .current
    ) -> String {
        let time = timeText(minute: proposal.displayedMinute, locale: locale)
        switch proposal.trigger {
        case .newTime: return "\(petName) suggests \(time)."
        case .reTime: return "This usually gets done around \(time)."
        }
    }

    /// The one-line subtext. New-time explains the evidence's breadth in
    /// the scope's own voice; re-time is the consent line - accurate
    /// about due-time semantics, silent about everything else.
    static func reason(
        _ proposal: SuggestionProposal, listName: String?, locale: Locale = .current
    ) -> String {
        if proposal.trigger == .reTime {
            return "Tap to change its due time from here on."
        }
        switch proposal.tier {
        case .series:
            let time = timeText(minute: proposal.displayedMinute, locale: locale)
            return "This one usually happens around \(time)."
        case .list:
            guard let listName else {
                // The list's name is gone - narrow the claim to the one
                // scope that needs no name, never widen the phrasing.
                return "You usually finish things \(bandPhrase(proposal.band))."
            }
            return "\(listName) things usually get done \(bandPhrase(proposal.band))."
        case .global:
            return "You usually finish things \(bandPhrase(proposal.band))."
        }
    }

    static func confirmed(minute: Int, locale: Locale = .current) -> String {
        "\(timeText(minute: minute, locale: locale)) set"
    }

    static func accessibilityLabel(
        _ proposal: SuggestionProposal, petName: String, listName: String?,
        locale: Locale = .current
    ) -> String {
        let time = timeText(minute: proposal.displayedMinute, locale: locale)
        let reason = reason(proposal, listName: listName, locale: locale)
        return "Set time to \(time). \(petName)'s suggestion: \(reason)"
    }

    static let dismissAccessibilityLabel = "Dismiss suggestion"

    /// The affirming band phrasing (night stays a rhythm, never a scold).
    static func bandPhrase(_ band: TimeOfDayBand) -> String {
        switch band {
        case .morning: "in the morning"
        case .afternoon: "in the afternoon"
        case .evening: "in the evening"
        case .night: "at night"
        }
    }
}
