//
//  AccountEraser.swift
//  MochiBuddy
//
//  Destroys the user's Firestore subtree for account deletion. Unlike the
//  everyday repositories these writes ARE awaited — deletion must reach the
//  server before the Auth user disappears (rules lock the orphaned data),
//  and the flow already requires being online for the auth delete.
//

import Foundation
import FirebaseFirestore

protocol AccountEraser: AnyObject {
    func eraseAllData(userId: String) async throws
}

final class FirestoreAccountEraser: AccountEraser {

    private let firestore: Firestore

    init(firestore: Firestore) {
        self.firestore = firestore
    }

    func eraseAllData(userId: String) async throws {
        let userDocument = firestore.collection("users").document(userId)
        try await deleteAllDocuments(in: userDocument.collection("tasks"))
        try await deleteAllDocuments(in: userDocument.collection("lists"))
        try await userDocument.delete()
    }

    private func deleteAllDocuments(in collection: CollectionReference) async throws {
        // Firestore caps a batch at 500 writes.
        let snapshot = try await collection.getDocuments()
        for chunk in snapshot.documents.chunked(into: 450) {
            let batch = firestore.batch()
            for document in chunk {
                batch.deleteDocument(document.reference)
            }
            try await batch.commit()
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
