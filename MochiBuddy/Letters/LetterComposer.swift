//
//  LetterComposer.swift
//  MochiBuddy
//
//  The pure composer (Personal Layer, Feature 3): PeriodSummary in, both
//  rendered variants out. No clock reads, no timezone reads, no
//  randomness - line variety comes from a stable hash of (periodId,
//  beatKey) over the pool with a don't-repeat-last-N check against the
//  synced archive, so composition is deterministic AND device-independent
//  without any stored rotation state.
//
//  Beat selection is two-phase: the class's structural beat goes first
//  and can never be displaced; optional beats fill remaining slots by
//  priority, one per category, with at most ONE insight-family beat
//  (observation XOR list return) - a three-beat letter must not contain
//  two separate "Mochi analyzed you" moments.
//

import Foundation

enum LetterComposer {

    struct ComposedLetter: Equatable {
        let classification: LetterClassification
        let beatTypes: [LetterBeatType]
        let lineIds: [String]
        let fullText: String
        let privateText: String
        let summaryHash: String
    }

    /// How many recent line ids the rotation avoids repeating.
    static let dontRepeatLastN = 6

    static func compose(summary: PeriodSummary) -> ComposedLetter {
        let classification = LetterClassifier.classify(summary)
        let avoid = Set(summary.priorLineIds.suffix(dontRepeatLastN))

        var beats: [(type: LetterBeatType, template: LetterTemplate, lineId: String)] = []

        func add(_ type: LetterBeatType, pool: [LetterTemplate], key: String) {
            let (template, lineId) = pick(
                pool, periodId: summary.periodId, key: key, avoiding: avoid
            )
            beats.append((type, template, lineId))
        }

        // Phase 1: the structural beat, first and undisplaceable.
        // Phase 2: optional fill by priority, capped per class.
        switch classification {
        case .quiet:
            // Salutation + one cozy beat + closing - the shortest letter
            // in the system, by design.
            add(.quiet, pool: LetterCopy.quietPool, key: "quiet")

        case .rough:
            // Presence first; at most one small true positive; nothing
            // else may enter - the restricted set is structural.
            add(.presence, pool: LetterCopy.presencePool, key: "presence")
            if summary.completionCount > 0 {
                add(.smallTruePositive, pool: LetterCopy.smallTruePositivePool, key: "small-positive")
            }

        case .vacationPartial:
            add(.vacation, pool: LetterCopy.vacationPool, key: "vacation")
            // slots is the TOTAL beat budget - fillOptionalBeats subtracts
            // the vacation beat above itself, so passing maxBeats - 1 here
            // would double-count it and cap vacation letters one short.
            fillOptionalBeats(
                into: &beats, summary: summary, avoid: avoid,
                slots: LetterConstants.maxBeats
            )

        case .great, .steady:
            fillOptionalBeats(
                into: &beats, summary: summary, avoid: avoid,
                slots: LetterConstants.maxBeats
            )
            // A steady week with no notable facts still deserves a beat:
            // the small-true-positive register fits and stays honest.
            if beats.isEmpty {
                add(.smallTruePositive, pool: LetterCopy.smallTruePositivePool, key: "small-positive")
            }
        }

        // Salutation + closing, register-matched.
        let (salutation, salutationId) = pick(
            LetterCopy.salutations(for: classification),
            periodId: summary.periodId, key: "salutation-\(classification.rawValue)", avoiding: avoid
        )
        let (closing, closingId) = pick(
            LetterCopy.closings(for: classification),
            periodId: summary.periodId, key: "closing-\(classification.rawValue)", avoiding: avoid
        )

        // Interpolation is per-beat: a best-day {weekday} and a comeback
        // {weekday} are different facts and must never cross paragraphs.
        let framing: [(type: LetterBeatType?, template: LetterTemplate)] =
            [(nil, salutation)] + beats.map { ($0.type, $0.template) } + [(nil, closing)]
        let fullBody = framing.map { render($0.template.full, beat: $0.type, summary: summary) }
        let privateBody = framing.map { render($0.template.priv, beat: $0.type, summary: summary) }
        let signature = PetCopyTemplate.render(LetterCopy.signature, petName: summary.petName)

        return ComposedLetter(
            classification: classification,
            beatTypes: beats.map(\.type),
            lineIds: [salutationId] + beats.map(\.lineId) + [closingId],
            fullText: (fullBody + [signature]).joined(separator: "\n\n"),
            privateText: (privateBody + [signature]).joined(separator: "\n\n"),
            summaryHash: summaryHash(summary)
        )
    }

    // MARK: - Optional beat fill

    private static func fillOptionalBeats(
        into beats: inout [(type: LetterBeatType, template: LetterTemplate, lineId: String)],
        summary: PeriodSummary,
        avoid: Set<String>,
        slots: Int
    ) {
        var remaining = slots - beats.count
        var insightUsed = false

        func add(_ type: LetterBeatType, pool: [LetterTemplate], key: String) {
            guard remaining > 0 else { return }
            let (template, lineId) = pick(
                pool, periodId: summary.periodId, key: key, avoiding: avoid
            )
            beats.append((type, template, lineId))
            remaining -= 1
        }

        // Priority: milestone > comeback > best day > observation > list
        // return. One per category; one insight-family beat total.
        // The milestone beat carries streak milestones, anniversaries, or
        // BOTH in one beat (Feature 2's collision rule: the streak owned
        // the banner and rundown that day; the letter remembers both).
        let hasStreakMilestone = !summary.milestonesLanded.isEmpty
        if hasStreakMilestone, summary.anniversary != nil {
            add(.milestone, pool: LetterCopy.milestoneCollisionPool, key: "milestone-both")
        } else if hasStreakMilestone {
            add(.milestone, pool: LetterCopy.milestonePool, key: "milestone")
        } else if let anniversary = summary.anniversary {
            add(
                .milestone,
                pool: anniversary.duringVacation
                    ? LetterCopy.anniversaryVacationPool
                    : LetterCopy.anniversaryPool,
                key: "milestone-anniversary"
            )
        }
        if summary.comeback != nil {
            add(.comeback, pool: LetterCopy.comebackPool, key: "comeback")
        }
        if summary.bestDay != nil {
            add(.bestDay, pool: LetterCopy.bestDayPool, key: "best-day")
        }
        if let conclusion = summary.observationConclusion, !insightUsed {
            add(.observation, pool: LetterCopy.observationPool(for: conclusion), key: "observation")
            insightUsed = true
        }
        if summary.listReturnName != nil, !insightUsed {
            add(.listReturn, pool: LetterCopy.listReturnPool, key: "list-return")
            insightUsed = true
        }
    }

    // MARK: - Deterministic rotation

    /// Stable pick: hash(periodId | key) indexes the pool; recently used
    /// line ids advance the cursor. Never `String.hashValue` - that is
    /// randomized per process and would break device-independence.
    static func pick(
        _ pool: [LetterTemplate], periodId: String, key: String, avoiding: Set<String>
    ) -> (LetterTemplate, String) {
        precondition(!pool.isEmpty, "every pool ships with lines")
        var index = Int(fnv1a("\(periodId)|\(key)") % UInt64(pool.count))
        for _ in 0..<pool.count {
            let lineId = "\(key):\(index)"
            if !avoiding.contains(lineId) {
                return (pool[index], lineId)
            }
            index = (index + 1) % pool.count
        }
        // Every line was recent (tiny pool, long streak): repeat is the
        // honest fallback.
        return (pool[index], "\(key):\(index)")
    }

    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    // MARK: - Rendering

    /// Interpolates exactly the facts that belong to one beat's paragraph;
    /// framing lines (salutation/closing, `beat == nil`) carry only {name}.
    private static func render(
        _ template: String, beat: LetterBeatType?, summary: PeriodSummary
    ) -> String {
        var text = template
        switch beat {
        case .bestDay:
            if let bestDay = summary.bestDay {
                text = text.replacingOccurrences(of: "{count}", with: LetterCopy.numberWord(bestDay.count))
                text = text.replacingOccurrences(of: "{weekday}", with: bestDay.weekdayName)
            }
        case .comeback:
            if let comeback = summary.comeback {
                // {task} exists only in full-variant templates by construction.
                text = text.replacingOccurrences(of: "{task}", with: comeback.taskTitle)
                text = text.replacingOccurrences(of: "{weekday}", with: comeback.completedWeekdayName)
            }
        case .milestone:
            if let milestone = summary.milestonesLanded.max() {
                text = text.replacingOccurrences(
                    of: "{milestone}", with: LetterCopy.numberWord(milestone)
                )
            }
            if let anniversary = summary.anniversary {
                text = text.replacingOccurrences(
                    of: "{annspan}", with: LetterCopy.anniversarySpan(anniversary.tier)
                )
            }
        case .observation:
            if case .weekday(let weekday) = summary.observationConclusion,
               ObservationCopy.weekdayNames.indices.contains(weekday), weekday >= 1 {
                // Observation weekday names are plural ("Tuesdays"); trim
                // where the template supplies its own trailing "s".
                let plural = ObservationCopy.weekdayNames[weekday]
                text = text.replacingOccurrences(of: "{weekday}s", with: plural)
                text = text.replacingOccurrences(of: "{weekday}", with: String(plural.dropLast()))
            }
        case .listReturn:
            if let list = summary.listReturnName {
                text = text.replacingOccurrences(of: "{list}", with: list)
            }
        default:
            break
        }
        return PetCopyTemplate.render(text, petName: summary.petName)
    }

    // MARK: - Provenance

    /// Non-reversible provenance for the stored letter: which facts the
    /// composer saw, never the facts themselves.
    static func summaryHash(_ summary: PeriodSummary) -> String {
        var parts: [String] = []
        parts.append(summary.periodId)
        parts.append(String(summary.completionCount))
        parts.append(String(summary.tasksDueCount))
        parts.append(String(summary.overdueDayCount))
        parts.append(summary.trailingAverage.map { String(format: "%.3f", $0) } ?? "-")
        parts.append(String(summary.vacationOverlap))
        if let bestDay = summary.bestDay {
            parts.append("\(bestDay.weekdayName):\(bestDay.count)")
        } else {
            parts.append("-")
        }
        parts.append(summary.milestonesLanded.map(String.init).joined(separator: ","))
        if let anniversary = summary.anniversary {
            parts.append("ann:\(anniversary.tier.telemetryLabel):\(anniversary.duringVacation)")
        } else {
            parts.append("-")
        }
        if let comeback = summary.comeback {
            parts.append("\(comeback.taskTitle)|\(comeback.completedWeekdayName)")
        } else {
            parts.append("-")
        }
        parts.append(summary.observationConclusion.map { String(describing: $0) } ?? "-")
        parts.append(summary.listReturnName ?? "-")
        parts.append(summary.petName)
        return String(format: "%016llx", fnv1a(parts.joined(separator: "|")))
    }
}
