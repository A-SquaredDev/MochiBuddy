//
//  ListRepository.swift
//  MochiBuddy
//
//  Abstracts users/{uid}/lists. Writes are fire-and-forget like the other
//  Firestore repositories — offline persistence applies them instantly.
//

import Foundation
import FirebaseFirestore

protocol ListRepository: AnyObject {
    func fetchLists(userId: String) async throws -> [TaskList]
    func createList(name: String, colorHex: String, icon: String, order: Int, userId: String) async throws
    func renameList(id: String, name: String, userId: String) async throws
    func deleteList(id: String, userId: String) async throws
    /// Persists a full reorder — ids in their new display order.
    func saveOrder(ids: [String], userId: String) async throws
}

final class FirestoreListRepository: ListRepository {

    private let firestore: Firestore

    init(firestore: Firestore) {
        self.firestore = firestore
    }

    private func lists(_ userId: String) -> CollectionReference {
        firestore.collection("users").document(userId).collection("lists")
    }

    func fetchLists(userId: String) async throws -> [TaskList] {
        let snapshot = try await lists(userId).order(by: "order").getDocuments()
        return snapshot.documents.map { document in
            let data = document.data()
            return TaskList(
                id: document.documentID,
                name: data["name"] as? String ?? "",
                colorHex: data["color"] as? String ?? TaskListDefaults.colorChoices[0],
                icon: data["icon"] as? String ?? TaskListDefaults.icon,
                order: data["order"] as? Int ?? 0
            )
        }
    }

    func createList(name: String, colorHex: String, icon: String, order: Int, userId: String) async throws {
        lists(userId).addDocument(data: [
            "name": name,
            "color": colorHex,
            "icon": icon,
            "order": order,
        ], completion: nil)
    }

    func renameList(id: String, name: String, userId: String) async throws {
        lists(userId).document(id).setData(["name": name], merge: true, completion: nil)
    }

    func deleteList(id: String, userId: String) async throws {
        lists(userId).document(id).delete(completion: nil)
    }

    func saveOrder(ids: [String], userId: String) async throws {
        let batch = firestore.batch()
        for (index, id) in ids.enumerated() {
            batch.setData(["order": index], forDocument: lists(userId).document(id), merge: true)
        }
        batch.commit(completion: nil)
    }
}
