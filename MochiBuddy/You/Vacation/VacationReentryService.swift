//
//  VacationReentryService.swift
//  MochiBuddy
//
//  The moment vacation mode is built around (design doc: Vacation mode →
//  Re-entry). Whether the trip ended by date, by the 30-day cap, or by
//  hand, everything routes through here: gather the "came due while you
//  were away" bucket for the triage sheet, seed the grace buffer so Mochi
//  wakes at ~content and drifts honestly over 24h, resume the streak
//  unchanged, clear the mode, and re-lay notifications. Never a punished
//  pet, never a permanent lie.
//

import Foundation

@MainActor
final class VacationReentryService {

    /// Bucket task ids waiting for the triage sheet - persisted so a
    /// manual end from the You tab (or a relaunch mid-re-entry) still
    /// surfaces triage on the next Home visit.
    static let pendingTriageKey = "mochi.vacation.pendingTriage"

    private let profileRepository: UserProfileRepository
    private let taskRepository: TaskRepository
    private let bufferStore: ComfortBufferStore
    private let relay: NotificationRelaying
    private let intervalRecorder: ObservationIntervalRecorder?
    private let momentWriter: MomentWriter?
    private let defaults: UserDefaults
    private let calendar: Calendar

    init(
        profileRepository: UserProfileRepository,
        taskRepository: TaskRepository,
        bufferStore: ComfortBufferStore,
        relay: NotificationRelaying,
        intervalRecorder: ObservationIntervalRecorder? = nil,
        momentWriter: MomentWriter? = nil,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.profileRepository = profileRepository
        self.taskRepository = taskRepository
        self.bufferStore = bufferStore
        self.relay = relay
        self.intervalRecorder = intervalRecorder
        self.momentWriter = momentWriter
        self.defaults = defaults
        self.calendar = calendar
    }

    /// A vacation that ended while the app was closed (fixed date passed,
    /// or the open-ended cap hit). Call on surface refresh; cheap no-op
    /// when there's nothing to process.
    func processIfEnded(profile: UserProfile, userId: String, now: Date = .now) async -> Bool {
        guard profile.vacationMode, !profile.vacationActive(at: now) else { return false }
        await finish(profile: profile, userId: userId, now: now)
        return true
    }

    /// The user ended it by hand (banner, You screen, or the check-in).
    func endNow(userId: String, now: Date = .now) async {
        guard let profile = try? await profileRepository.fetchProfile(userId: userId),
              profile.vacationMode
        else { return }
        await finish(profile: profile, userId: userId, now: now)
    }

    /// Bucket ids waiting for the triage sheet, resolved against live
    /// tasks (completed/deleted ones silently drop out).
    func pendingTriageIds() -> [String] {
        defaults.stringArray(forKey: Self.pendingTriageKey) ?? []
    }

    func clearPendingTriage() {
        defaults.removeObject(forKey: Self.pendingTriageKey)
    }

    // MARK: - Open-ended long-run check-in

    static let checkInSnoozeKey = "mochi.vacation.checkinSnoozedUntil"

    /// Show the gentle "still away?" card: open-ended vacation, two weeks
    /// in, and not recently snoozed. In-app only - never a push.
    func checkInDue(profile: UserProfile, now: Date = .now) -> Bool {
        guard profile.vacationMode,
              profile.vacationActive(at: now),
              profile.vacationResumeAt == nil,
              let started = profile.vacationStartedAt,
              now.timeIntervalSince(started) >= TimeInterval(VacationConstants.checkinDays) * 24 * 3600
        else { return false }
        if let snoozedUntil = defaults.object(forKey: Self.checkInSnoozeKey) as? Date,
           now < snoozedUntil {
            return false
        }
        return true
    }

    /// "Keep resting" - the card re-arms after another interval; the hard
    /// cap still applies regardless.
    func snoozeCheckIn(now: Date = .now) {
        defaults.set(
            now.addingTimeInterval(TimeInterval(VacationConstants.checkinDays) * 24 * 3600),
            forKey: Self.checkInSnoozeKey
        )
    }

    // MARK: - The re-entry itself

    private func finish(profile: UserProfile, userId: String, now: Date) async {
        // The window this vacation actually covered: entry to whichever
        // came first, the scheduled/capped end or right now (manual end).
        let scheduledEnd = VacationSchedule.effectiveEnd(
            startedAt: profile.vacationStartedAt,
            resumeAt: profile.vacationResumeAt
        )
        let end = min(scheduledEnd ?? now, now)

        // The observation log records the interval this vacation TRULY
        // covered - a trip that expired days ago closes at its scheduled
        // end, not at this open (Feature 4: momentum eligibility).
        await intervalRecorder?.vacationEnded(at: end)

        // Journal record (Feature 6): the return moment, keyed by the
        // interval's start, plus any deferrable anniversaries the trip
        // covered on their TRUE dates. Written at re-entry, never during.
        if let started = profile.vacationStartedAt {
            await momentWriter?.vacationEnded(
                intervalStart: started, end: end, adoptedOn: profile.adoptedOn, now: now
            )
        }

        // The bucket: one-off dated tasks overdue as of the end - both the
        // ones that crossed during the trip and anything already overdue
        // at entry (its stress was cleared then, it gets triaged now).
        // Recurring tasks stay out: the roll-forward invariant already
        // bounds them, and Monday's vitamins aren't takeable on Wednesday.
        let tasks = (try? await taskRepository.incompleteTasks(userId: userId)) ?? []
        let bucket = tasks.filter { task in
            task.repeatRule == nil
                && !task.completed
                && task.dueAt != nil
                && (MoodEngine.overdueBoundary(task, calendar: calendar).map { $0 <= end } ?? false)
        }
        if !bucket.isEmpty {
            defaults.set(bucket.map(\.id), forKey: Self.pendingTriageKey)
        }

        // Grace buffer: wake at ~content regardless of the true pile,
        // drifting down over 24h. Reuses the comfort-buffer machinery -
        // clamped by the same cap as every other boost.
        let baseline = MoodEngine.baseline(
            incompleteTasks: tasks,
            completionsLast24h: 0.0,
            vacationMode: false,
            now: now,
            calendar: calendar
        )
        let lift = min(MoodEngine.Constants.bufferCap, max(0, VacationConstants.graceWake - baseline))
        if lift > 0 {
            bufferStore.add(lift: lift, duration: VacationConstants.graceDecay)
        }

        // The streak froze, it never broke: if no completion landed since
        // before the trip, move lastActive to yesterday so today continues
        // the chain exactly as if they'd never left.
        if profile.streakCount > 0,
           let lastActive = profile.lastActiveDate,
           let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.startOfDay(for: lastActive) < yesterday {
            try? await profileRepository.saveStreak(
                count: profile.streakCount,
                best: profile.bestStreakCount,
                // Pass-through, never a stamp: re-entry sets no record.
                bestAchievedOn: profile.bestStreakAchievedOn,
                lastActiveDate: yesterday,
                userId: userId
            )
        }

        try? await profileRepository.saveVacation(
            mode: false, resumeAt: nil, startedAt: nil, userId: userId
        )
        defaults.removeObject(forKey: Self.checkInSnoozeKey)
        relay.requestRelay(.vacationChange)
    }
}
