//
//  TaskRepository.swift
//  MochiBuddy
//
//  Abstracts users/{uid}/tasks. Onboarding only needs capture + count;
//  the full task surface comes with the home screen build.
//

import Foundation
import FirebaseFirestore

protocol TaskRepository: AnyObject {
    func addTask(_ draft: TaskDraft, userId: String) async throws
    func incompleteTaskCount(userId: String) async throws -> Int
}

final class FirestoreTaskRepository: TaskRepository {

    private let firestore: Firestore

    init(firestore: Firestore) {
        self.firestore = firestore
    }

    private func tasks(_ userId: String) -> CollectionReference {
        firestore.collection("users").document(userId).collection("tasks")
    }

    func addTask(_ draft: TaskDraft, userId: String) async throws {
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
        // Not awaited: offline persistence applies the write to the local
        // cache instantly; awaiting would block until a server ack.
        tasks(userId).addDocument(data: fields, completion: nil)
    }

    func incompleteTaskCount(userId: String) async throws -> Int {
        let query = tasks(userId).whereField("completed", isEqualTo: false).count
        let snapshot = try await query.getAggregation(source: .server)
        return snapshot.count.intValue
    }
}
