//
//  NudgeCenterTests.swift
//  MochiBuddyTests
//
//  The setup-nudge decision core is pure: context + ledger state + now in,
//  at most one topic out. These tests encode the pacing rules - priority,
//  global spacing, per-topic cooldown, retirement, and the suppressions.
//

import Foundation
import Testing
import UserNotifications
@testable import MochiBuddy

private func makeContext(
    notificationStatus: UNAuthorizationStatus = .authorized,
    widgetInstalled: Bool? = true,
    remindersConnected: Bool = true,
    isLapsed: Bool = false,
    onVacation: Bool = false,
    accountAgeDays: Int? = 10
) -> NudgeCenter.Context {
    NudgeCenter.Context(
        notificationStatus: notificationStatus,
        widgetInstalled: widgetInstalled,
        remindersConnected: remindersConnected,
        isLapsed: isLapsed,
        onVacation: onVacation,
        accountAgeDays: accountAgeDays
    )
}

@Suite("NudgeCenter · decision core")
struct NudgeCenterTests {

    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("fully set up: no nudge at all")
    func allSetUpIsSilent() {
        #expect(NudgeCenter.nextTopic(
            context: makeContext(), state: NudgeLedger.State(), now: now
        ) == nil)
    }

    @Test("priority: notifications beat widget beat reminders")
    func priorityOrder() {
        let allNeeded = makeContext(
            notificationStatus: .provisional, widgetInstalled: false, remindersConnected: false
        )
        #expect(NudgeCenter.nextTopic(
            context: allNeeded, state: NudgeLedger.State(), now: now
        ) == .notifications)

        let noNotifNeed = makeContext(widgetInstalled: false, remindersConnected: false)
        #expect(NudgeCenter.nextTopic(
            context: noNotifNeed, state: NudgeLedger.State(), now: now
        ) == .widget)

        let remindersOnly = makeContext(remindersConnected: false)
        #expect(NudgeCenter.nextTopic(
            context: remindersOnly, state: NudgeLedger.State(), now: now
        ) == .remindersImport)
    }

    @Test("notDetermined, provisional, and denied all count as needing notifications")
    func notificationStatuses() {
        for status: UNAuthorizationStatus in [.notDetermined, .provisional, .denied] {
            #expect(NudgeCenter.nextTopic(
                context: makeContext(notificationStatus: status),
                state: NudgeLedger.State(), now: now
            ) == .notifications)
        }
        #expect(NudgeCenter.nextTopic(
            context: makeContext(notificationStatus: .authorized),
            state: NudgeLedger.State(), now: now
        ) == nil)
    }

    @Test("unknown widget state never nudges - only a confirmed absence does")
    func unknownWidgetSkips() {
        #expect(NudgeCenter.nextTopic(
            context: makeContext(widgetInstalled: nil),
            state: NudgeLedger.State(), now: now
        ) == nil)
    }

    @Test("lapsed, vacation, and young accounts suppress everything")
    func suppressions() {
        let needy = { (mutate: (inout NudgeCenter.Context) -> Void) -> NudgeCenter.Context in
            var context = makeContext(notificationStatus: .denied)
            mutate(&context)
            return context
        }
        #expect(NudgeCenter.nextTopic(
            context: needy { $0.isLapsed = true }, state: NudgeLedger.State(), now: now
        ) == nil)
        #expect(NudgeCenter.nextTopic(
            context: needy { $0.onVacation = true }, state: NudgeLedger.State(), now: now
        ) == nil)
        #expect(NudgeCenter.nextTopic(
            context: needy { $0.accountAgeDays = 1 }, state: NudgeLedger.State(), now: now
        ) == nil)
        #expect(NudgeCenter.nextTopic(
            context: needy { $0.accountAgeDays = nil }, state: NudgeLedger.State(), now: now
        ) == nil)
    }

    @Test("the global spacing gates ANY nudge, not just the same topic")
    func globalSpacing() {
        var state = NudgeLedger.State()
        state.lastNudgeShownAt = now.addingTimeInterval(-NudgeConstants.minSpacing + 3600)
        #expect(NudgeCenter.nextTopic(
            context: makeContext(remindersConnected: false), state: state, now: now
        ) == nil)

        state.lastNudgeShownAt = now.addingTimeInterval(-NudgeConstants.minSpacing - 3600)
        #expect(NudgeCenter.nextTopic(
            context: makeContext(remindersConnected: false), state: state, now: now
        ) == .remindersImport)
    }

    @Test("a topic on cooldown yields to the next eligible topic")
    func topicCooldownYields() {
        // Notifications shown 13d23h ago: past the 5d global spacing, but
        // still inside its own 14d cooldown - widget takes the slot.
        let lastShown = now.addingTimeInterval(-(NudgeConstants.topicCooldown - 3600))
        var state = NudgeLedger.State()
        state.topics[NudgeTopic.notifications.rawValue] = NudgeLedger.TopicState(
            shownCount: 1, lastShownAt: lastShown
        )
        state.lastNudgeShownAt = lastShown
        let context = makeContext(notificationStatus: .provisional, widgetInstalled: false)
        #expect(NudgeCenter.nextTopic(context: context, state: state, now: now) == .widget)
    }

    @Test("acted and dismissed-out topics retire for good")
    func retirement() {
        var state = NudgeLedger.State()
        state.topics[NudgeTopic.remindersImport.rawValue] = NudgeLedger.TopicState(actedAt: now)
        #expect(NudgeCenter.nextTopic(
            context: makeContext(remindersConnected: false), state: state, now: now
        ) == nil)

        state.topics[NudgeTopic.remindersImport.rawValue] = NudgeLedger.TopicState(
            dismissCount: NudgeConstants.maxDismissals
        )
        #expect(NudgeCenter.nextTopic(
            context: makeContext(remindersConnected: false), state: state, now: now
        ) == nil)

        state.topics[NudgeTopic.remindersImport.rawValue] = NudgeLedger.TopicState(
            shownCount: NudgeConstants.maxShowsPerTopic
        )
        #expect(NudgeCenter.nextTopic(
            context: makeContext(remindersConnected: false), state: state, now: now
        ) == nil)
    }

    @Test("denied gets Settings copy; the rest get the in-app prompt")
    func bannerCopy() {
        let denied = NudgeCenter.banner(for: .notifications, status: .denied, petName: "Nori")
        #expect(denied.action == .openSystemSettings)
        #expect(denied.text.contains("Nori"))

        let quiet = NudgeCenter.banner(for: .notifications, status: .provisional, petName: "Nori")
        #expect(quiet.action == .openNotificationSettings)

        #expect(NudgeCenter.banner(for: .widget, status: .authorized, petName: "Nori")
            .action == .showWidgetHelp)
        #expect(NudgeCenter.banner(for: .remindersImport, status: .authorized, petName: "Nori")
            .action == .openAppleReminders)
    }
}

@Suite("NudgeLedger")
@MainActor
struct NudgeLedgerTests {

    private func makeLedger() -> NudgeLedger {
        NudgeLedger(defaults: UserDefaults(suiteName: "nudge-ledger-\(UUID())")!)
    }

    @Test("shown/dismissed/acted round-trip per UID")
    func roundTrip() {
        let ledger = makeLedger()
        ledger.recordShown(.widget, userId: "u1")
        ledger.recordDismissed(.widget, userId: "u1")
        ledger.recordActed(.notifications, userId: "u1")

        let state = ledger.state(userId: "u1")
        #expect(state.topics[NudgeTopic.widget.rawValue]?.shownCount == 1)
        #expect(state.topics[NudgeTopic.widget.rawValue]?.dismissCount == 1)
        #expect(state.topics[NudgeTopic.notifications.rawValue]?.actedAt != nil)
        #expect(state.lastNudgeShownAt != nil)

        #expect(ledger.state(userId: "u2") == NudgeLedger.State(), "UIDs are isolated")
    }

    @Test("clear wipes only the given UID")
    func clearIsScoped() {
        let ledger = makeLedger()
        ledger.recordShown(.widget, userId: "u1")
        ledger.recordShown(.widget, userId: "u2")
        ledger.clear(userId: "u1")
        #expect(ledger.state(userId: "u1") == NudgeLedger.State())
        #expect(ledger.state(userId: "u2").topics[NudgeTopic.widget.rawValue]?.shownCount == 1)
    }
}
