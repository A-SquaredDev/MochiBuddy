//
//  TaskRepository.swift
//  MochiBuddy
//
//  Abstracts users/{uid}/tasks. Onboarding only needs capture + count;
//  the full task surface comes with the home screen build.
//

import Foundation
import FirebaseFirestore

/// One completion as a fact about the user's behavior - the stats screen
/// and the observation engine (Personal Layer, Feature 4) both read this.
/// Local context is captured at completion time; rows that predate the
/// capture are re-interpreted under the current zone and honestly marked
/// `localContextDerived` (the documented fallback, which decays out of
/// the observation window naturally).
struct CompletedTaskStat: Equatable {

    enum Source: String {
        case mochi
        case apple
    }

    /// Internal id; enables diversity gates, never leaves the device.
    let taskId: String
    /// Stable across a recurring task's occurrences (first occurrence's id).
    let seriesId: String?
    let completedAt: Date
    /// YYYY-MM-DD in the zone where completed.
    let completedLocalDate: String
    /// Minutes since local midnight in the zone where completed, 0...1439.
    let completedLocalMinute: Int
    /// IANA id of the zone at completion.
    let completionTimeZone: String
    /// True when the local fields were back-derived under the current zone
    /// rather than stamped at completion.
    let localContextDerived: Bool
    let dueAt: Date?
    let hasTime: Bool
    let listId: String?
    let isRecurring: Bool
    let source: Source
    /// nil = unknown (never treated as 0; 0 means known-unmoved).
    let rescheduleCount: Int?
    /// Nominal effort minutes the task carried at completion; nil = unrated.
    /// Read-path only (D6) - the stat is never written, it reads the task doc.
    let estimatedMinutes: Int?

    init(
        taskId: String = "",
        seriesId: String? = nil,
        completedAt: Date,
        dueAt: Date?,
        listId: String? = nil,
        hasTime: Bool = false,
        isRecurring: Bool = false,
        source: Source = .mochi,
        rescheduleCount: Int? = nil,
        estimatedMinutes: Int? = nil,
        localContext: CompletionLocalContext? = nil,
        localContextDerived: Bool = false
    ) {
        self.taskId = taskId
        self.seriesId = seriesId
        self.completedAt = completedAt
        self.dueAt = dueAt
        self.listId = listId
        self.hasTime = hasTime
        self.isRecurring = isRecurring
        self.source = source
        self.rescheduleCount = rescheduleCount
        self.estimatedMinutes = estimatedMinutes
        // No stored context: interpret under the current zone, marked
        // derived - the documented fallback for legacy rows.
        let context = localContext ?? .capture(at: completedAt)
        self.completedLocalDate = context.localDate
        self.completedLocalMinute = context.localMinute
        self.completionTimeZone = context.timeZoneId
        self.localContextDerived = localContext == nil || localContextDerived
    }
}

/// Where a completed-history page ended - the next page starts strictly
/// after this. Two fields because completedAt is client-stamped and
/// collisions (widget drains) are unlikely but not impossible; the
/// documentID tiebreak makes the cursor exact for free.
struct CompletedPageCursor: Equatable {
    let completedAt: Date
    let documentID: String
}

struct CompletedTasksPage: Equatable {
    let items: [TaskItem]
    /// nil when this page reached the end of history.
    let nextCursor: CompletedPageCursor?
}

protocol TaskRepository: AnyObject {
    /// Mints a task id without writing anything - the suggestion chip's
    /// dismissal ledger keys unsaved tasks by it, so a dismissal made
    /// before the first save survives the save (Personal Layer, Feature 5).
    func allocateTaskId(userId: String) -> String
    /// Returns the new task's id (available immediately - offline persistence
    /// applies the write to the local cache before the server ack).
    /// `id` saves under a preallocated identity; nil mints one.
    @discardableResult
    func addTask(_ draft: TaskDraft, id: String?, userId: String) async throws -> String
    func incompleteTasks(userId: String) async throws -> [TaskItem]
    /// One task by id - notification actions resolve their target with it.
    func task(id: String, userId: String) async throws -> TaskItem?
    /// Most recent completions, newest first.
    func completedTasks(limit: Int, userId: String) async throws -> [TaskItem]
    /// Completions on/after `since`, newest first.
    func completedTasks(since: Date, userId: String) async throws -> [TaskItem]
    /// `localContext` is the completion-time local stamp; nil means "the
    /// completion is happening right now" and the repository captures it.
    /// Widget-drained completions pass the context stamped at tap time.
    func setCompleted(taskId: String, completed: Bool, localContext: CompletionLocalContext?, completedAt: Date?, userId: String) async throws
    /// Rewrites the editable fields from the domain model.
    /// `countingReschedule` also increments the procrastination counter -
    /// pass true only for a user move of an incomplete task's due date to
    /// a later day (never for skip-occurrence, vacation triage, or a move
    /// earlier - those are different intents).
    func updateTask(_ task: TaskItem, countingReschedule: Bool, userId: String) async throws
    /// Pushes the due date and increments the procrastination counter.
    func snoozeTask(id: String, to newDueAt: Date, userId: String) async throws
    /// Re-stamps a rolled-forward recurring occurrence and silently logs
    /// the missed ones (one-live-occurrence invariant). Distinct from
    /// snooze - a roll is the calendar moving on, not the user deferring,
    /// so it never touches rescheduleCount.
    func rollForwardTask(id: String, to newDueAt: Date, missedOccurrences: Int, userId: String) async throws
    func deleteTask(id: String, userId: String) async throws
    func incompleteTaskCount(userId: String) async throws -> Int
    func totalTaskCount(userId: String) async throws -> Int
    func completedTaskStats(since: Date, userId: String) async throws -> [CompletedTaskStat]
    /// One page of completed history, newest first. A nil cursor is page
    /// one; the Done tab's infinite scroll walks the cursor chain.
    func completedTasksPage(
        limit: Int, after cursor: CompletedPageCursor?, userId: String
    ) async throws -> CompletedTasksPage
    /// Exact completion count via a server aggregation - the "N done this
    /// week" number must never be capped by whatever page happens to be
    /// loaded.
    func completedTaskCount(since: Date, userId: String) async throws -> Int
    /// A real list's own recent completions, independent of global
    /// recency - fixes ListDetail's done-section starvation. The Inbox
    /// (listId nil) has no indexable predicate (Firestore cannot query
    /// field absence) and keeps the filter-a-global-page approach.
    func completedTasks(listId: String, limit: Int, userId: String) async throws -> [TaskItem]

    // Server-backed variants for the letter composition barrier ONLY
    // (Personal Layer, Feature 3): composing over stale cache would
    // deterministically write the wrong letter and win the race. Every
    // other read in the app stays cache-friendly.
    func completedTaskStatsFromServer(since: Date, userId: String) async throws -> [CompletedTaskStat]
    func completedTasksFromServer(since: Date, userId: String) async throws -> [TaskItem]
    func incompleteTasksFromServer(userId: String) async throws -> [TaskItem]
}

extension TaskRepository {
    @discardableResult
    func addTask(_ draft: TaskDraft, userId: String) async throws -> String {
        try await addTask(draft, id: nil, userId: userId)
    }

    func updateTask(_ task: TaskItem, userId: String) async throws {
        try await updateTask(task, countingReschedule: false, userId: userId)
    }
}

final class FirestoreTaskRepository: TaskRepository {

    private let firestore: Firestore

    init(firestore: Firestore) {
        self.firestore = firestore
    }

    private func tasks(_ userId: String) -> CollectionReference {
        firestore.collection("users").document(userId).collection("tasks")
    }

    func allocateTaskId(userId: String) -> String {
        tasks(userId).document().documentID
    }

    @discardableResult
    func addTask(_ draft: TaskDraft, id: String?, userId: String) async throws -> String {
        var fields: [String: Any] = [
            "title": draft.title,
            "hasTime": draft.hasTime,
            "dueTimeZone": TimeZone.current.identifier,
            "priority": draft.priority.rawValue,
            "completed": false,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "order": 0,
            "rescheduleCount": 0,
            "source": "mochi",
        ]
        if let notes = draft.notes {
            fields["notes"] = notes
        }
        if let dueAt = draft.dueAt {
            fields["dueAt"] = Timestamp(date: dueAt)
        }
        if let listId = draft.listId {
            fields["listId"] = listId
        }
        if let rule = draft.repeatRule {
            fields["repeatRule"] = Self.repeatRuleFields(rule)
        }
        if let seriesId = draft.seriesId {
            fields["seriesId"] = seriesId
        }
        if let estimatedMinutes = draft.estimatedMinutes {
            fields["estimatedMinutes"] = estimatedMinutes
        }
        FirestoreReadLog.recordWrite(Self.self)
        // Not awaited: offline persistence applies the write to the local
        // cache instantly; awaiting would block until a server ack.
        if let id {
            tasks(userId).document(id).setData(fields, completion: nil)
            return id
        }
        return tasks(userId).addDocument(data: fields, completion: nil).documentID
    }

    func completedTasks(limit: Int, userId: String) async throws -> [TaskItem] {
        FirestoreReadLog.record(Self.self)
        // Range + order on the same field - no composite index needed
        // (completedAt only exists on completed tasks). Epoch, not
        // .distantPast - year 1 is outside Timestamp's valid range.
        let snapshot = try await tasks(userId)
            .whereField("completedAt", isGreaterThan: Timestamp(date: Date(timeIntervalSince1970: 0)))
            .order(by: "completedAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.map(Self.taskItem(from:))
    }

    func completedTasks(since: Date, userId: String) async throws -> [TaskItem] {
        FirestoreReadLog.record(Self.self)
        // Range + order on the same field - no composite index needed.
        let snapshot = try await tasks(userId)
            .whereField("completedAt", isGreaterThanOrEqualTo: Timestamp(date: since))
            .order(by: "completedAt", descending: true)
            .getDocuments()
        return snapshot.documents.map(Self.taskItem(from:))
    }

    func completedTasksPage(
        limit: Int, after cursor: CompletedPageCursor?, userId: String
    ) async throws -> CompletedTasksPage {
        FirestoreReadLog.record(Self.self)
        // Range + first order stay on completedAt (the range-field-first
        // rule); the __name__ order is the implicit tiebreak made explicit
        // so the cursor can include it. Firestore serves field + __name__
        // orderings from the single-field index - no composite needed.
        var query = tasks(userId)
            .whereField("completedAt", isGreaterThan: Timestamp(date: Date(timeIntervalSince1970: 0)))
            .order(by: "completedAt", descending: true)
            .order(by: FieldPath.documentID(), descending: true)
            .limit(to: limit)
        if let cursor {
            query = query.start(after: [Timestamp(date: cursor.completedAt), cursor.documentID])
        }
        let snapshot = try await query.getDocuments()
        let items = snapshot.documents.map(Self.taskItem(from:))
        let nextCursor: CompletedPageCursor? = items.count < limit
            ? nil
            : items.last.flatMap { last in
                last.completedAt.map { CompletedPageCursor(completedAt: $0, documentID: last.id) }
            }
        return CompletedTasksPage(items: items, nextCursor: nextCursor)
    }

    func completedTaskCount(since: Date, userId: String) async throws -> Int {
        FirestoreReadLog.record(Self.self)
        let query = tasks(userId)
            .whereField("completedAt", isGreaterThanOrEqualTo: Timestamp(date: since))
            .count
        let snapshot = try await query.getAggregation(source: .server)
        return snapshot.count.intValue
    }

    func completedTasks(listId: String, limit: Int, userId: String) async throws -> [TaskItem] {
        FirestoreReadLog.record(Self.self)
        // The one query needing a composite index (tasks: listId ASC,
        // completedAt DESC) - created in the Firebase console. Callers
        // fall back to the global page on error, so shipping ahead of the
        // index degrades to the old behavior instead of breaking.
        let snapshot = try await tasks(userId)
            .whereField("listId", isEqualTo: listId)
            .order(by: "completedAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.map(Self.taskItem(from:))
    }

    func updateTask(_ task: TaskItem, countingReschedule: Bool, userId: String) async throws {
        FirestoreReadLog.recordWrite(Self.self)
        var fields: [String: Any] = [
            "title": task.title,
            "hasTime": task.hasTime,
            "dueTimeZone": TimeZone.current.identifier,
            "priority": task.priority.rawValue,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        fields["notes"] = task.notes ?? FieldValue.delete()
        fields["dueAt"] = task.dueAt.map(Timestamp.init(date:)) ?? FieldValue.delete()
        fields["listId"] = task.listId ?? FieldValue.delete()
        fields["repeatRule"] = task.repeatRule.map(Self.repeatRuleFields) ?? FieldValue.delete()
        fields["estimatedMinutes"] = task.estimatedMinutes ?? FieldValue.delete()
        if countingReschedule {
            // Server-side increment, never a value off the domain model -
            // an offline queue of edits still counts each push exactly once.
            fields["rescheduleCount"] = FieldValue.increment(Int64(1))
        }
        tasks(userId).document(task.id).setData(fields, merge: true, completion: nil)
    }

    func snoozeTask(id: String, to newDueAt: Date, userId: String) async throws {
        FirestoreReadLog.recordWrite(Self.self)
        tasks(userId).document(id).setData([
            "dueAt": Timestamp(date: newDueAt),
            "rescheduleCount": FieldValue.increment(Int64(1)),
            "updatedAt": FieldValue.serverTimestamp(),
        ], merge: true, completion: nil)
    }

    func rollForwardTask(id: String, to newDueAt: Date, missedOccurrences: Int, userId: String) async throws {
        FirestoreReadLog.recordWrite(Self.self)
        tasks(userId).document(id).setData([
            "dueAt": Timestamp(date: newDueAt),
            "missedCount": FieldValue.increment(Int64(missedOccurrences)),
            "lastMissedAt": Timestamp(date: .now),
            "updatedAt": FieldValue.serverTimestamp(),
        ], merge: true, completion: nil)
    }

    func deleteTask(id: String, userId: String) async throws {
        FirestoreReadLog.recordWrite(Self.self)
        tasks(userId).document(id).delete(completion: nil)
    }

    func incompleteTasks(userId: String) async throws -> [TaskItem] {
        FirestoreReadLog.record(Self.self)
        // Single equality filter - no composite index needed; today/overdue
        // grouping happens client-side (task counts stay small).
        let snapshot = try await tasks(userId)
            .whereField("completed", isEqualTo: false)
            .getDocuments()
        return snapshot.documents.map(Self.taskItem(from:))
    }

    func setCompleted(taskId: String, completed: Bool, localContext: CompletionLocalContext?, completedAt: Date?, userId: String) async throws {
        FirestoreReadLog.recordWrite(Self.self)
        var fields: [String: Any] = [
            "completed": completed,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if completed {
            // Client time, not serverTimestamp - the mood engine and stats
            // read it from the local cache immediately. A widget drain
            // passes the tap instant so a stale tap never books into
            // today's momentum window; live check-offs stamp now.
            fields["completedAt"] = Timestamp(date: completedAt ?? .now)
            // Completion-local context, stamped at the source (Personal
            // Layer, Feature 4): the day/minute/zone the user acted in.
            let context = localContext ?? .capture()
            fields["completedLocalDate"] = context.localDate
            fields["completedLocalMinute"] = context.localMinute
            fields["completionTimeZone"] = context.timeZoneId
        } else {
            fields["completedAt"] = FieldValue.delete()
            fields["completedLocalDate"] = FieldValue.delete()
            fields["completedLocalMinute"] = FieldValue.delete()
            fields["completionTimeZone"] = FieldValue.delete()
        }
        tasks(userId).document(taskId).setData(fields, merge: true, completion: nil)
    }

    private static func repeatRuleFields(_ rule: TaskRepeat) -> [String: Any] {
        var fields: [String: Any] = ["freq": rule.freq, "interval": 1]
        if let days = rule.customDays {
            fields["days"] = days
        }
        return fields
    }

    private static func repeatRule(from data: [String: Any]?) -> TaskRepeat? {
        guard let freq = data?["freq"] as? String else { return nil }
        return TaskRepeat(freq: freq, days: data?["days"] as? [Int])
    }

    func task(id: String, userId: String) async throws -> TaskItem? {
        FirestoreReadLog.record(Self.self)
        let snapshot = try await tasks(userId).document(id).getDocument()
        guard snapshot.exists, let data = snapshot.data() else { return nil }
        return Self.taskItem(id: snapshot.documentID, data: data)
    }

    private static func taskItem(from document: QueryDocumentSnapshot) -> TaskItem {
        taskItem(id: document.documentID, data: document.data())
    }

    private static func taskItem(id: String, data: [String: Any]) -> TaskItem {
        return TaskItem(
            id: id,
            title: data["title"] as? String ?? "",
            notes: data["notes"] as? String,
            dueAt: (data["dueAt"] as? Timestamp)?.dateValue(),
            hasTime: data["hasTime"] as? Bool ?? false,
            priority: TaskPriority(rawValue: data["priority"] as? String ?? "") ?? .med,
            listId: data["listId"] as? String,
            repeatRule: Self.repeatRule(from: data["repeatRule"] as? [String: Any]),
            completed: data["completed"] as? Bool ?? false,
            completedAt: (data["completedAt"] as? Timestamp)?.dateValue(),
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
            seriesId: data["seriesId"] as? String,
            rescheduleCount: data["rescheduleCount"] as? Int,
            estimatedMinutes: data["estimatedMinutes"] as? Int
        )
    }

    func incompleteTaskCount(userId: String) async throws -> Int {
        FirestoreReadLog.record(Self.self)
        let query = tasks(userId).whereField("completed", isEqualTo: false).count
        let snapshot = try await query.getAggregation(source: .server)
        return snapshot.count.intValue
    }

    func totalTaskCount(userId: String) async throws -> Int {
        FirestoreReadLog.record(Self.self)
        let snapshot = try await tasks(userId).count.getAggregation(source: .server)
        return snapshot.count.intValue
    }

    func completedTaskStats(since: Date, userId: String) async throws -> [CompletedTaskStat] {
        try await completedTaskStats(since: since, userId: userId, source: .default)
    }

    func completedTaskStatsFromServer(since: Date, userId: String) async throws -> [CompletedTaskStat] {
        try await completedTaskStats(since: since, userId: userId, source: .server)
    }

    func completedTasksFromServer(since: Date, userId: String) async throws -> [TaskItem] {
        FirestoreReadLog.record(Self.self)
        let snapshot = try await tasks(userId)
            .whereField("completedAt", isGreaterThanOrEqualTo: Timestamp(date: since))
            .order(by: "completedAt", descending: true)
            .getDocuments(source: .server)
        return snapshot.documents.map(Self.taskItem(from:))
    }

    func incompleteTasksFromServer(userId: String) async throws -> [TaskItem] {
        FirestoreReadLog.record(Self.self)
        let snapshot = try await tasks(userId)
            .whereField("completed", isEqualTo: false)
            .getDocuments(source: .server)
        return snapshot.documents.map(Self.taskItem(from:))
    }

    private func completedTaskStats(
        since: Date, userId: String, source: FirestoreSource
    ) async throws -> [CompletedTaskStat] {
        FirestoreReadLog.record(Self.self)
        // Range on completedAt alone (no composite index needed) - the field
        // only exists on completed tasks.
        let snapshot = try await tasks(userId)
            .whereField("completedAt", isGreaterThanOrEqualTo: Timestamp(date: since))
            .getDocuments(source: source)
        return snapshot.documents.compactMap { document in
            let data = document.data()
            guard let completedAt = (data["completedAt"] as? Timestamp)?.dateValue() else {
                return nil
            }
            // Stored completion-time context when present; rows predating
            // the stamp fall back to derivation under the current zone in
            // the CompletedTaskStat initializer, marked derived.
            var context: CompletionLocalContext?
            if let localDate = data["completedLocalDate"] as? String,
               let localMinute = data["completedLocalMinute"] as? Int,
               let zone = data["completionTimeZone"] as? String {
                context = CompletionLocalContext(
                    localDate: localDate, localMinute: localMinute, timeZoneId: zone
                )
            }
            return CompletedTaskStat(
                taskId: document.documentID,
                seriesId: data["seriesId"] as? String,
                completedAt: completedAt,
                dueAt: (data["dueAt"] as? Timestamp)?.dateValue(),
                listId: data["listId"] as? String,
                hasTime: data["hasTime"] as? Bool ?? false,
                isRecurring: data["repeatRule"] != nil || data["seriesId"] != nil,
                source: CompletedTaskStat.Source(rawValue: data["source"] as? String ?? "") ?? .mochi,
                rescheduleCount: data["rescheduleCount"] as? Int,
                estimatedMinutes: data["estimatedMinutes"] as? Int,
                localContext: context
            )
        }
    }
}
