//
//  WidgetStateMirror.swift
//  MochiBuddy
//
//  The app-side half of the App Group contract: after every re-lay,
//  mirror the world into MochiWidgetState and poke WidgetKit. The stored
//  curve is the same baseline the notification planner just scheduled
//  against, so a widget refresh and a mood ping are the same
//  pre-evaluation of the same curve - they cannot contradict each other.
//

import Foundation
import WidgetKit

@MainActor
final class WidgetStateMirror {

    enum Constants {
        /// Baseline sampling step for the stored curve.
        static let resolution: TimeInterval = 30 * 60
        /// Mirrored horizon - reads the scheduler's so a tuned
        /// notif_horizon_days can't desync "the timeline IS the forecast".
        static var horizonDays: Int { NotificationOrchestrator.Constants.horizonDays }
    }

    private let themeStore: ThemeStore
    private let defaults: UserDefaults
    private let calendar: Calendar
    /// Injected so tests can capture instead of poking WidgetKit.
    private let reloadWidgets: () -> Void

    init(
        themeStore: ThemeStore,
        defaults: UserDefaults = MochiAppGroup.defaults,
        calendar: Calendar = .current,
        reloadWidgets: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.themeStore = themeStore
        self.defaults = defaults
        self.calendar = calendar
        self.reloadWidgets = reloadWidgets
    }

    /// Build and write the snapshot from a relay's context - called from
    /// the orchestrator's post-lay hook, the one choke point every
    /// mutation already passes through.
    func mirror(context: NotificationOrchestrator.RelayContext, now: Date = .now) {
        let snapshot = context.snapshot

        let onVacation = VacationSchedule.isActive(
            mode: snapshot.vacationMode,
            startedAt: snapshot.vacationStartedAt,
            resumeAt: snapshot.vacationResumeAt,
            at: now
        )
        let displayState: MochiWidgetState.DisplayState = context.lapsed
            ? .lapsed
            : onVacation ? .vacation : .active

        var points: [MochiWidgetState.ForecastPoint] = []
        let end = calendar.date(byAdding: .day, value: Constants.horizonDays, to: now) ?? now
        var t = now
        while t <= end {
            points.append(.init(
                date: t,
                value: MoodForecast.baseline(at: t, snapshot: snapshot, calendar: calendar)
            ))
            t = t.addingTimeInterval(Constants.resolution)
        }

        let top = RundownRanker.topTasks(from: snapshot.tasks, at: now, calendar: calendar)
        let state = MochiWidgetState(
            displayState: displayState,
            themeId: themeStore.current.id,
            mochiName: context.petName,
            baseline: points,
            hideTaskNames: context.prefs.hideTaskNames,
            nextTasks: top.map { task in
                .init(
                    id: task.id,
                    title: task.title,
                    dueAt: task.dueAt,
                    hasTime: task.hasTime,
                    completable: true
                )
            },
            vacationEnd: onVacation
                ? VacationSchedule.effectiveEnd(
                    startedAt: snapshot.vacationStartedAt,
                    resumeAt: snapshot.vacationResumeAt
                )
                : nil,
            lastComputed: now
        )
        WidgetStateStore.save(state, defaults: defaults)
        reloadWidgets()
    }
}
