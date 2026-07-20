//
//  NotificationPlanDiffTests.swift
//  MochiBuddyTests
//
//  The re-lay contract: promises survive every lay unless their task is
//  genuinely gone, stale mood pings are wiped, and identifiers we don't
//  own are never touched.
//

import Foundation
import Testing
@testable import MochiBuddy

private func promise(_ taskId: String, at fireAt: Date = Dates.hours(2)) -> PlannedNotification {
    PlannedNotification(
        id: NotificationID.due(taskId: taskId), kind: .promise, fireAt: fireAt, taskId: taskId
    )
}

private func moodPing(at fireAt: Date, band: MoodBand = .anxious) -> PlannedNotification {
    PlannedNotification(
        id: NotificationID.mood(band: band, fireAt: fireAt),
        kind: .moodPing, fireAt: fireAt, band: band
    )
}

@Suite("NotificationPlanDiffer")
struct NotificationPlanDiffTests {

    @Test("a still-desired promise is never in the removal set - re-lays cannot drop a reminder")
    func promiseSurvivesRelay() {
        let keep = promise("t1")
        let diff = NotificationPlanDiffer.diff(
            desired: [keep, moodPing(at: Dates.hours(4))],
            pendingIds: ["due-t1", "mood-1-999", "mood-1-1000"]
        )
        #expect(!diff.removeIds.contains("due-t1"))
        #expect(diff.schedule.contains(keep), "same-id re-add replaces atomically")
    }

    @Test("stale mood pings and backstop are wiped when no longer desired")
    func staleMoodWiped() {
        let diff = NotificationPlanDiffer.diff(
            desired: [promise("t1")],
            pendingIds: ["due-t1", "mood-0-123", "mood-2-456", "backstop"]
        )
        #expect(Set(diff.removeIds) == ["mood-0-123", "mood-2-456", "backstop"])
    }

    @Test("a completed or deleted task's promise IS removed - its id left the desired set")
    func goneTaskPromiseRemoved() {
        let diff = NotificationPlanDiffer.diff(
            desired: [promise("t2")],
            pendingIds: ["due-t1", "due-t2"]
        )
        #expect(diff.removeIds == ["due-t1"])
    }

    @Test("identifiers we don't own are never touched, whatever they are")
    func foreignIdsUntouched() {
        let diff = NotificationPlanDiffer.diff(
            desired: [],
            pendingIds: ["someOtherSDK-42", "due-t1", "rundown-2026-07-09"]
        )
        #expect(Set(diff.removeIds) == ["due-t1", "rundown-2026-07-09"])
        #expect(!diff.removeIds.contains("someOtherSDK-42"))
    }

    @Test("an empty desired plan clears exactly our pending set (vacation entry, notifications off)")
    func emptyPlanClearsOurs() {
        let diff = NotificationPlanDiffer.diff(
            desired: [],
            pendingIds: ["due-t1", "mood-4-1", "rundown-2026-07-09", "backstop"]
        )
        #expect(Set(diff.removeIds) == ["due-t1", "mood-4-1", "rundown-2026-07-09", "backstop"])
        #expect(diff.schedule.isEmpty)
    }
}
