//
//  DevFixturesSection.swift
//  MochiBuddy
//
//  DevScheduler card for the suggestion fixture seeder, with the
//  walkthrough sheet the release-checklist QA pass follows. Compiled
//  behind #if DEBUG - physically absent from release.
//

#if DEBUG

import SwiftUI

struct DevFixturesSection: View {
    let statusText: String
    let onSeedNewTime: () -> Void
    let onSeedReTime: () -> Void
    let onSeedDoneHistory: () -> Void
    let onDelete: () -> Void

    @Environment(\.mochiTheme) private var theme
    @State private var showHelp = false

    var body: some View {
        MochiCard(padding: EdgeInsets(top: 12, leading: 15, bottom: 12, trailing: 15)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Test fixtures")
                        .font(MochiFont.body(11, weight: .heavy))
                        .foregroundStyle(theme.muted)
                    Spacer()
                    Button {
                        showHelp = true
                    } label: {
                        Label("How to use", systemImage: "questionmark.circle")
                            .font(MochiFont.body(11, weight: .heavy))
                    }
                    .foregroundStyle(theme.primaryText)
                }
                Text("Writes real completion history so the suggested-times chip and the Done tab pagination can be tested without weeks of usage. Test data: delete when done.")
                    .font(MochiFont.body(9.5, weight: .bold))
                    .foregroundStyle(theme.muted)
                Button("Seed new-time fixture (18 evening completions)", action: onSeedNewTime)
                Button("Seed re-time fixture (9:00 series done at 19:00)", action: onSeedReTime)
                Button("Seed done-history fixture (36 done, 4 recent days)", action: onSeedDoneHistory)
                Button("Delete fixtures", action: onDelete)
                    .foregroundStyle(theme.danger)
                if !statusText.isEmpty {
                    Text(statusText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.muted)
                }
            }
            .font(MochiFont.body(11, weight: .heavy))
            .foregroundStyle(theme.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showHelp) {
            DevFixtureHelpView()
        }
    }
}

struct DevFixtureHelpView: View {
    @Environment(\.mochiTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("What this is", """
                    The suggestion engine only speaks with real evidence: \
                    about 15 completions clustered at a consistent time \
                    across 5 different days. These buttons write that \
                    history into the signed-in account so you can watch \
                    the feature fire today instead of using the app \
                    faithfully for three weeks.

                    The seeded docs are real Firestore completions, so \
                    Stats, Best Hours, the Done tab, and the Journal will \
                    see them too. Use a dev or test account, and delete \
                    the fixtures when the pass is over.
                    """)

                    section("Pass 1: the new-time chip", """
                    1. Tap Seed new-time fixture. It creates a "Seeded \
                    fixtures" list holding 18 completed tasks, done \
                    around 19:00 across six past days.
                    2. Go to Tasks and create a new task. Give it a \
                    title, set its due date to TOMORROW, leave the time \
                    unset, and pick the Seeded fixtures list.
                    3. The suggestion chip should appear near the time \
                    control, proposing about 7:00 PM with a reason line.
                    4. Cross-check: back here, the Suggestions inspector \
                    shows every gate passing for that scope (evidence, \
                    dates, peak share, runner-up).
                    5. Tap the chip to accept: the time fills with the \
                    proposal. Hand-editing it afterwards must still work.
                    6. Open another new task on the same list and dismiss \
                    the chip instead. Reopen: it stays gone. It only \
                    returns if a new proposal differs by an hour or more.

                    Why tomorrow: a task due today inside 30 minutes of \
                    the proposal is silenced by the lead-time guardrail, \
                    and 19:00 may already be past when you test.
                    """)

                    section("Pass 2: re-time and the badge", """
                    1. Tap Seed re-time fixture. It creates a daily \
                    recurring "[Seed] Daily review" scheduled at 9:00 AM \
                    whose eight past occurrences were completed around \
                    7:00 PM, plus one live occurrence due tomorrow.
                    2. Go to Tasks: the live row should carry the small \
                    re-time badge (a circling clock). The badge may also \
                    show inside the list's detail screen. It must NEVER \
                    appear on Home or on an Apple Reminders row.
                    3. Open the task. The re-time suggestion should \
                    offer moving the due time to about 7:00 PM, with \
                    copy that says due time and persists forward.
                    4. Accept, save, and confirm the series' next \
                    occurrence now carries the new time.
                    """)

                    section("Pass 3: Done tab pagination", """
                    1. Tap Seed done-history fixture. It writes 36 \
                    completed tasks onto a "Seeded done history" list, \
                    9 per day across the 4 most recent days that sit \
                    clear of the last 48 hours, with times scattered \
                    through the day so no suggestion peak forms.
                    2. Tasks, then Done: the first page holds 30 rows. \
                    Scrolling near the bottom shows shimmer rows, then \
                    the older days appear. The Load older button does \
                    the same under VoiceOver.
                    3. The "N done this week" line shows the exact \
                    count (36 plus your own recent ones), not a number \
                    capped at 30.
                    4. Run early in a month and the seeded days land \
                    in the previous month, so the month divider \
                    appears while scrolling. Mid-month, complete one \
                    real task today and scroll instead; the divider \
                    check then needs organic older history.
                    5. Keep loading to the very end: the "whole story" \
                    footnote appears and the spinner stops.
                    """)

                    section("Negative checks", """
                    With fixtures seeded, the chip must still stay away:
                    1. Lapsed: relaunch with -mochiStartLapsed. No chip, \
                    no badge anywhere.
                    2. Bedtime: set bedtime so 19:00 falls inside it. \
                    The new-time chip goes quiet (silence, not a \
                    clamped different time).
                    3. A task due TODAY when it is already past 18:30: \
                    silenced by the 30 minute lead guardrail.
                    """)

                    section("Cleanup", """
                    Tap Delete fixtures. It removes every seeded task \
                    and both seeded lists, then the Suggestions \
                    inspector should show the gates failing again \
                    (honest silence on thin data). Seeding twice without \
                    deleting is blocked so evidence counts stay exact.

                    If the app was deleted and reinstalled between seed \
                    and cleanup, the id ledger is gone: delete the \
                    seeded lists by hand in the app and remove the \
                    [Seed] rows from the Done tab.
                    """)
                }
                .padding(18)
            }
            .background(theme.bg)
            .navigationTitle("Fixture seeder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(MochiFont.display(15, weight: .semibold))
                .foregroundStyle(theme.ink)
            Text(body)
                .font(MochiFont.body(12, weight: .medium))
                .foregroundStyle(theme.ink.opacity(0.85))
        }
    }
}

#endif
