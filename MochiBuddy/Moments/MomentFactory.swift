//
//  MomentFactory.swift
//  MochiBuddy
//
//  Pure payload derivation: (immutable event facts) -> Moment. Every
//  producer funnels through here so a natural id maps to exactly one
//  canonical payload - the create-only write can race freely because the
//  loser's document would have been content-identical (spec edge 3).
//  Nothing here looks anything up; snapshot inputs travel with the event.
//

import Foundation

enum MomentFactory {

    /// Adoption. `petName` is the name captured at the naming beat; nil
    /// for backfilled/synthesized adoptions where the name on that day is
    /// unknowable (legacy-safe copy carries no name).
    static func adoption(
        adoptedOn: String, petName: String?, locale: Locale, now: Date
    ) -> Moment {
        let rendered = petName.map(MomentCopy.adoption(petName:)) ?? MomentCopy.adoptionLegacy
        return moment(
            id: "adoption-\(adoptedOn)",
            type: .adoption,
            occurredOn: adoptedOn,
            rendered: rendered,
            petName: petName,
            subjectName: nil,
            sourceEventId: nil,
            locale: locale,
            now: now
        )
    }

    /// Anniversary, on its TRUE date (deferred acknowledgments included -
    /// the mark's own day, never the day it was noticed). The id is the
    /// milestone's own stable identity. Copy is deliberately name-free,
    /// so the payload cannot drift under an in-flight rename.
    static func anniversary(
        _ milestone: AnniversaryMilestone, locale: Locale, now: Date
    ) -> Moment {
        moment(
            id: milestone.id,
            type: .anniversary,
            occurredOn: milestone.day.dateString,
            rendered: MomentCopy.anniversary(tier: milestone.tier),
            petName: nil,
            subjectName: nil,
            sourceEventId: nil,
            locale: locale,
            now: now
        )
    }

    /// Streak milestone at its crossing edge. A rebuilt streak reaching
    /// the same count on a later date is a NEW event - the date is part
    /// of the identity.
    static func streakMilestone(
        count: Int, day: String, petName: String, locale: Locale, now: Date
    ) -> Moment {
        moment(
            id: "streak-milestone-\(count)-\(day)",
            type: .streakMilestone,
            occurredOn: day,
            rendered: MomentCopy.streakMilestone(count: count, petName: petName),
            petName: petName,
            subjectName: nil,
            sourceEventId: nil,
            locale: locale,
            now: now
        )
    }

    /// Vacation return, keyed by the interval's synced start instant -
    /// end-reenter-end on one date is two intervals, two moments.
    /// `endDay` is the trip's TRUE end date (stamped at re-entry).
    static func vacationReturn(
        intervalStart: Date, endDay: String, petName: String, locale: Locale, now: Date
    ) -> Moment {
        moment(
            id: "vacation-return-\(Int(intervalStart.timeIntervalSince1970))",
            type: .vacationReturn,
            occurredOn: endDay,
            rendered: MomentCopy.vacationReturn(petName: petName),
            petName: petName,
            subjectName: nil,
            sourceEventId: nil,
            locale: locale,
            now: now
        )
    }

    /// List return, keyed by Feature 4's event identity (list + the civil
    /// day the return fired). The list's name is frozen here, as of the
    /// event - a later rename or delete never rewrites the timeline.
    static func listReturn(
        listId: String, firedOn: String, listName: String, locale: Locale, now: Date
    ) -> Moment {
        moment(
            id: "list-return-\(listId)-\(firedOn)",
            type: .listReturn,
            occurredOn: firedOn,
            rendered: MomentCopy.listReturn(listName: listName),
            petName: nil,
            subjectName: listName,
            sourceEventId: "listReturn:\(listId)|\(firedOn)",
            locale: locale,
            now: now
        )
    }

    private static func moment(
        id: String,
        type: MomentType,
        occurredOn: String,
        rendered: String,
        petName: String?,
        subjectName: String?,
        sourceEventId: String?,
        locale: Locale,
        now: Date
    ) -> Moment {
        Moment(
            id: id,
            type: type,
            occurredOn: occurredOn,
            renderedTextSnapshot: rendered,
            accessibilityTextSnapshot: MomentCopy.accessibilityText(
                rendered: rendered, occurredOn: occurredOn, locale: locale
            ),
            petNameSnapshot: petName,
            subjectNameSnapshot: subjectName,
            localeIdentifier: locale.identifier,
            copyDeckVersion: MomentCopy.deckVersion,
            sourceEventId: sourceEventId,
            createdAt: now
        )
    }
}
