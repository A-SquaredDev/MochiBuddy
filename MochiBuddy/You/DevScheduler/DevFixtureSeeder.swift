//
//  DevFixtureSeeder.swift
//  MochiBuddy
//
//  Seeds qualifying completion history so the suggested-times feature can
//  be verified live without three weeks of real usage (release-checklist
//  section 4), plus a bulk done-history fixture for the Done tab
//  pagination pass (manual-test-plan 1b). The suggestion fixtures are
//  each sized to clear every engine gate with margin:
//
//  New-time: 18 one-off completions on a dedicated list, 3 per day across
//  6 distinct past days (the obs_day_cap is 3, so nothing is wasted),
//  clustered 18:40 to 19:15. Clears list scope: evidence 18 >= 15, dates
//  6 >= 5, peak share 1.0 >= 0.35, peak dates 6 >= 3, no runner-up
//  window, 18 distinct identities with none over 40 percent.
//
//  Re-time: a daily recurring series scheduled at 09:00 whose 8 completed
//  occurrences (8 distinct days, all timed) landed around 19:00. Clears
//  series scope (8 >= 8 timed, 8 >= 5 dates, all in peak) with a 600
//  minute mismatch >= the 180 required. One live occurrence due tomorrow
//  09:00 keeps the one-live-occurrence invariant.
//
//  Done-history: 36 completions, 9 per day across the 4 most recent days
//  that sit clear of the last 48 hours, on its own "Seeded done history"
//  list. 36 beats both the 30-row Done page and the rolling-7-day week
//  count, so page two, the exact "N done this week" number, and the
//  end-of-history footnote are all reachable. Times scatter across
//  08:00-22:00 (no 3-hour window holds 35 percent), and day capping runs
//  per scope, so the suggestion fixtures' gates stay untouched.
//
//  Writes go through the container's decorated repositories, so the
//  observation memo invalidates and the task cache stays truthful, and
//  every doc is indistinguishable from a real completion. Rewards are
//  untouched by design: the repository-level completion write never runs
//  the completion store, so no coins, no streak, no celebration.
//
//  Seeded ids persist in UserDefaults per uid so deletion is exact.
//  Compiled behind #if DEBUG - physically absent from release.
//

#if DEBUG

import Foundation

final class DevFixtureSeeder {

    private struct SeededState: Codable {
        var listId: String?
        var taskIds: [String] = []
        var newTimeSeeded = false
        var reTimeSeeded = false
        // Optionals so states saved before the done-history fixture
        // existed still decode instead of resetting the ledger.
        var doneListId: String?
        var doneSeeded: Bool?
    }

    private let taskRepository: TaskRepository
    private let listRepository: ListRepository
    private let authRepository: AuthRepository
    private let defaults: UserDefaults

    init(
        taskRepository: TaskRepository,
        listRepository: ListRepository,
        authRepository: AuthRepository,
        defaults: UserDefaults = .standard
    ) {
        self.taskRepository = taskRepository
        self.listRepository = listRepository
        self.authRepository = authRepository
        self.defaults = defaults
    }

    // MARK: - Fixtures

    func seedNewTime() async -> String {
        guard let uid = authRepository.currentAccount?.uid else {
            return "no signed-in user"
        }
        var seeded = load(uid)
        guard !seeded.newTimeSeeded else {
            return "new-time fixture already seeded; delete fixtures first"
        }
        guard let listId = await ensureList(uid: uid, state: &seeded) else {
            return "could not create the fixture list"
        }

        // 3 completions per day (the day cap) across 6 distinct days, all
        // inside the 42-day observation window, none inside the last 48h
        // so today's mood momentum stays untouched.
        let dayOffsets = [3, 5, 7, 10, 12, 14]
        let baseMinutes = [1120, 1140, 1155] // 18:40, 19:00, 19:15
        var count = 0
        for (dayIndex, offset) in dayOffsets.enumerated() {
            for (slot, base) in baseMinutes.enumerated() {
                // Deterministic jitter keeps the cluster organic while
                // staying well inside the plus/minus 90 minute peak window.
                let minute = base + (dayIndex * 3 + slot * 2) % 10
                guard let (day, instant) = pastInstant(daysAgo: offset, minute: minute) else { continue }
                let id = taskRepository.allocateTaskId(userId: uid)
                let draft = TaskDraft(
                    title: "[Seed] Evening task \(count + 1)",
                    dueAt: day,
                    hasTime: false,
                    priority: .med,
                    listId: listId
                )
                do {
                    try await taskRepository.addTask(draft, id: id, userId: uid)
                    try await taskRepository.setCompleted(
                        taskId: id, completed: true,
                        localContext: .capture(at: instant), completedAt: instant,
                        userId: uid
                    )
                    seeded.taskIds.append(id)
                    count += 1
                } catch {
                    save(seeded, uid: uid)
                    return "seed failed after \(count) tasks: \(error.localizedDescription)"
                }
            }
        }
        seeded.newTimeSeeded = true
        save(seeded, uid: uid)
        return "seeded \(count) completions around 19:00 on the Seeded fixtures list"
    }

    func seedReTime() async -> String {
        guard let uid = authRepository.currentAccount?.uid else {
            return "no signed-in user"
        }
        var seeded = load(uid)
        guard !seeded.reTimeSeeded else {
            return "re-time fixture already seeded; delete fixtures first"
        }
        let listId = await ensureList(uid: uid, state: &seeded)

        // First occurrence keeps seriesId nil (its own id is the series
        // identity, exactly like a real spawn chain); the rest inherit it.
        let seriesId = taskRepository.allocateTaskId(userId: uid)
        let dayOffsets = [3, 5, 7, 9, 11, 13, 15, 17]
        var count = 0
        for (index, offset) in dayOffsets.enumerated() {
            guard let (_, dueAt) = pastInstant(daysAgo: offset, minute: 9 * 60),
                  let (_, completedAt) = pastInstant(daysAgo: offset, minute: 1140 + (index * 5) % 15)
            else { continue }
            let id = index == 0 ? seriesId : taskRepository.allocateTaskId(userId: uid)
            let draft = TaskDraft(
                title: "[Seed] Daily review",
                dueAt: dueAt,
                hasTime: true,
                priority: .med,
                listId: listId,
                repeatRule: .daily,
                seriesId: index == 0 ? nil : seriesId
            )
            do {
                try await taskRepository.addTask(draft, id: id, userId: uid)
                try await taskRepository.setCompleted(
                    taskId: id, completed: true,
                    localContext: .capture(at: completedAt), completedAt: completedAt,
                    userId: uid
                )
                seeded.taskIds.append(id)
                count += 1
            } catch {
                save(seeded, uid: uid)
                return "seed failed after \(count) occurrences: \(error.localizedDescription)"
            }
        }

        // The one live occurrence, due tomorrow 09:00: not today, so the
        // 30 minute lead guardrail and the recurrence roller stay out of
        // the picture.
        guard let tomorrow = futureInstant(daysAhead: 1, minute: 9 * 60) else {
            save(seeded, uid: uid)
            return "seeded history but could not compute tomorrow"
        }
        let liveId = taskRepository.allocateTaskId(userId: uid)
        let liveDraft = TaskDraft(
            title: "[Seed] Daily review",
            dueAt: tomorrow,
            hasTime: true,
            priority: .med,
            listId: listId,
            repeatRule: .daily,
            seriesId: seriesId
        )
        do {
            try await taskRepository.addTask(liveDraft, id: liveId, userId: uid)
            seeded.taskIds.append(liveId)
        } catch {
            save(seeded, uid: uid)
            return "seeded history but the live occurrence failed: \(error.localizedDescription)"
        }
        seeded.reTimeSeeded = true
        save(seeded, uid: uid)
        return "seeded \(count) past occurrences at 19:00 plus a live one due tomorrow 09:00"
    }

    func seedDoneHistory() async -> String {
        guard let uid = authRepository.currentAccount?.uid else {
            return "no signed-in user"
        }
        var seeded = load(uid)
        guard seeded.doneSeeded != true else {
            return "done-history fixture already seeded; delete fixtures first"
        }
        guard let listId = await ensureDoneList(uid: uid, state: &seeded) else {
            return "could not create the done-history list"
        }

        // Offsets 3-6 keep every instant clear of the 48-hour mood
        // window even at a 22:00 slot, while the oldest 08:00 slot still
        // lands inside the rolling 7-day week count. The 157-minute
        // stride is coprime with the 840-minute span, so the 36 times
        // spread near-uniformly and no suggestion peak can form.
        let dayOffsets = [3, 4, 5, 6]
        var count = 0
        for (dayIndex, offset) in dayOffsets.enumerated() {
            for slot in 0..<9 {
                let minute = 480 + ((dayIndex * 9 + slot) * 157) % 840
                guard let (day, instant) = pastInstant(daysAgo: offset, minute: minute) else { continue }
                let id = taskRepository.allocateTaskId(userId: uid)
                let draft = TaskDraft(
                    title: "[Seed] Done history \(count + 1)",
                    dueAt: day,
                    hasTime: false,
                    priority: .med,
                    listId: listId
                )
                do {
                    try await taskRepository.addTask(draft, id: id, userId: uid)
                    try await taskRepository.setCompleted(
                        taskId: id, completed: true,
                        localContext: .capture(at: instant), completedAt: instant,
                        userId: uid
                    )
                    seeded.taskIds.append(id)
                    count += 1
                } catch {
                    save(seeded, uid: uid)
                    return "seed failed after \(count) tasks: \(error.localizedDescription)"
                }
            }
        }
        seeded.doneSeeded = true
        save(seeded, uid: uid)
        return "seeded \(count) completions across 4 recent days on the Seeded done history list"
    }

    func deleteFixtures() async -> String {
        guard let uid = authRepository.currentAccount?.uid else {
            return "no signed-in user"
        }
        let seeded = load(uid)
        guard seeded.listId != nil || seeded.doneListId != nil || !seeded.taskIds.isEmpty else {
            return "nothing seeded"
        }
        var removed = 0
        for id in seeded.taskIds {
            if (try? await taskRepository.deleteTask(id: id, userId: uid)) != nil {
                removed += 1
            }
        }
        if let listId = seeded.listId {
            try? await listRepository.deleteList(id: listId, userId: uid)
        }
        if let doneListId = seeded.doneListId {
            try? await listRepository.deleteList(id: doneListId, userId: uid)
        }
        defaults.removeObject(forKey: key(uid))
        return "removed \(removed) seeded tasks and the fixture lists"
    }

    // MARK: - Helpers

    private func ensureList(uid: String, state: inout SeededState) async -> String? {
        if let listId = state.listId { return listId }
        guard let list = try? await listRepository.createList(
            name: "Seeded fixtures",
            colorHex: TaskListDefaults.colorChoices[5],
            icon: "hammer.fill",
            order: 99,
            userId: uid
        ) else { return nil }
        state.listId = list.id
        save(state, uid: uid)
        return list.id
    }

    private func ensureDoneList(uid: String, state: inout SeededState) async -> String? {
        if let listId = state.doneListId { return listId }
        guard let list = try? await listRepository.createList(
            name: "Seeded done history",
            colorHex: TaskListDefaults.colorChoices[2],
            icon: "checkmark.circle.fill",
            order: 98,
            userId: uid
        ) else { return nil }
        state.doneListId = list.id
        save(state, uid: uid)
        return list.id
    }

    /// Midnight-anchored day plus an instant at `minute` past local
    /// midnight, `daysAgo` back from today.
    private func pastInstant(daysAgo: Int, minute: Int) -> (day: Date, instant: Date)? {
        let calendar = Calendar.current
        guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: .now)),
              let instant = calendar.date(byAdding: .minute, value: minute, to: day)
        else { return nil }
        return (day, instant)
    }

    private func futureInstant(daysAhead: Int, minute: Int) -> Date? {
        let calendar = Calendar.current
        guard let day = calendar.date(byAdding: .day, value: daysAhead, to: calendar.startOfDay(for: .now))
        else { return nil }
        return calendar.date(byAdding: .minute, value: minute, to: day)
    }

    private func key(_ uid: String) -> String { "mochi.devFixtures.\(uid)" }

    private func load(_ uid: String) -> SeededState {
        guard let data = defaults.data(forKey: key(uid)),
              let state = try? JSONDecoder().decode(SeededState.self, from: data)
        else { return SeededState() }
        return state
    }

    private func save(_ state: SeededState, uid: String) {
        defaults.set(try? JSONEncoder().encode(state), forKey: key(uid))
    }
}

#endif
