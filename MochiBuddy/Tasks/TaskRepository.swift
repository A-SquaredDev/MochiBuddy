//
//  TaskRepository.swift
//  MochiBuddy
//
//  Abstracts users/{uid}/tasks. Onboarding only needs capture + count;
//  the full task surface comes with the home screen build.
//

import Foundation
import FirebaseFirestore

/// The slice of a completed task the stats screen needs.
struct CompletedTaskStat: Equatable {
    let completedAt: Date
    let dueAt: Date?
}

protocol TaskRepository: AnyObject {
    /// Returns the new task's id (available immediately — offline persistence
    /// applies the write to the local cache before the server ack).
    @discardableResult
    func addTask(_ draft: TaskDraft, userId: String) async throws -> String
    func incompleteTasks(userId: String) async throws -> [TaskItem]
    /// Most recent completions, newest first.
    func completedTasks(limit: Int, userId: String) async throws -> [TaskItem]
    func setCompleted(taskId: String, completed: Bool, userId: String) async throws
    /// Rewrites the editable fields from the domain model.
    func updateTask(_ task: TaskItem, userId: String) async throws
    /// Pushes the due date and increments the procrastination counter.
    func snoozeTask(id: String, to newDueAt: Date, userId: String) async throws
    func deleteTask(id: String, userId: String) async throws
    func incompleteTaskCount(userId: String) async throws -> Int
    func totalTaskCount(userId: String) async throws -> Int
    func completedTaskStats(since: Date, userId: String) async throws -> [CompletedTaskStat]
}

final class FirestoreTaskRepository: TaskRepository {

    private let firestore: Firestore

    init(firestore: Firestore) {
        self.firestore = firestore
    }

    private func tasks(_ userId: String) -> CollectionReference {
        firestore.collection("users").document(userId).collection("tasks")
    }

    @discardableResult
    func addTask(_ draft: TaskDraft, userId: String) async throws -> String {
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
        // Not awaited: offline persistence applies the write to the local
        // cache instantly; awaiting would block until a server ack.
        return tasks(userId).addDocument(data: fields, completion: nil).documentID
    }

    func completedTasks(limit: Int, userId: String) async throws -> [TaskItem] {
        // Range + order on the same field — no composite index needed
        // (completedAt only exists on completed tasks). Epoch, not
        // .distantPast — year 1 is outside Timestamp's valid range.
        let snapshot = try await tasks(userId)
            .whereField("completedAt", isGreaterThan: Timestamp(date: Date(timeIntervalSince1970: 0)))
            .order(by: "completedAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.map(Self.taskItem(from:))
    }

    func updateTask(_ task: TaskItem, userId: String) async throws {
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
        tasks(userId).document(task.id).setData(fields, merge: true, completion: nil)
    }

    func snoozeTask(id: String, to newDueAt: Date, userId: String) async throws {
        tasks(userId).document(id).setData([
            "dueAt": Timestamp(date: newDueAt),
            "rescheduleCount": FieldValue.increment(Int64(1)),
            "updatedAt": FieldValue.serverTimestamp(),
        ], merge: true, completion: nil)
    }

    func deleteTask(id: String, userId: String) async throws {
        tasks(userId).document(id).delete(completion: nil)
    }

    func incompleteTasks(userId: String) async throws -> [TaskItem] {
        // Single equality filter — no composite index needed; today/overdue
        // grouping happens client-side (task counts stay small).
        let snapshot = try await tasks(userId)
            .whereField("completed", isEqualTo: false)
            .getDocuments()
        return snapshot.documents.map(Self.taskItem(from:))
    }

    func setCompleted(taskId: String, completed: Bool, userId: String) async throws {
        var fields: [String: Any] = [
            "completed": completed,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        // Client time, not serverTimestamp — the mood engine and stats read
        // it from the local cache immediately.
        fields["completedAt"] = completed ? Timestamp(date: .now) : FieldValue.delete()
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

    private static func taskItem(from document: QueryDocumentSnapshot) -> TaskItem {
        let data = document.data()
        return TaskItem(
            id: document.documentID,
            title: data["title"] as? String ?? "",
            notes: data["notes"] as? String,
            dueAt: (data["dueAt"] as? Timestamp)?.dateValue(),
            hasTime: data["hasTime"] as? Bool ?? false,
            priority: TaskPriority(rawValue: data["priority"] as? String ?? "") ?? .med,
            listId: data["listId"] as? String,
            repeatRule: Self.repeatRule(from: data["repeatRule"] as? [String: Any]),
            completed: data["completed"] as? Bool ?? false,
            completedAt: (data["completedAt"] as? Timestamp)?.dateValue(),
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
        )
    }

    func incompleteTaskCount(userId: String) async throws -> Int {
        let query = tasks(userId).whereField("completed", isEqualTo: false).count
        let snapshot = try await query.getAggregation(source: .server)
        return snapshot.count.intValue
    }

    func totalTaskCount(userId: String) async throws -> Int {
        let snapshot = try await tasks(userId).count.getAggregation(source: .server)
        return snapshot.count.intValue
    }

    func completedTaskStats(since: Date, userId: String) async throws -> [CompletedTaskStat] {
        // Range on completedAt alone (no composite index needed) — the field
        // only exists on completed tasks.
        let snapshot = try await tasks(userId)
            .whereField("completedAt", isGreaterThanOrEqualTo: Timestamp(date: since))
            .getDocuments()
        return snapshot.documents.compactMap { document in
            let data = document.data()
            guard let completedAt = (data["completedAt"] as? Timestamp)?.dateValue() else {
                return nil
            }
            return CompletedTaskStat(
                completedAt: completedAt,
                dueAt: (data["dueAt"] as? Timestamp)?.dateValue()
            )
        }
    }
}
