//
//  MomentRepository.swift
//  MochiBuddy
//
//  users/{uid}/moments/{naturalKeyId} - synced, create-only Journal
//  moments. Writes follow the activityWeeks discipline (guard-then-set,
//  fire-and-forget): the natural key makes duplicates structurally
//  impossible and payloads are deterministic, so unlike letters no
//  transaction is needed - a racing loser's rejected write would have
//  been content-identical anyway.
//

import Foundation
import FirebaseFirestore

protocol MomentRepository: AnyObject {
    /// The full moment set, newest first. Cache-friendly - moments accrue
    /// at relationship speed (a handful per month), so v1 reads the whole
    /// collection; month-bounded paging can slot in behind this API.
    func moments(userId: String) async throws -> [Moment]
    /// Create-only, idempotent: no-op when the document already exists.
    func ensureMoment(_ moment: Moment, userId: String) async
}

/// Field encoding shared with the adoption batch write (the profile
/// repository writes the adoption moment atomically with `adoptedOn`).
enum MomentFields {

    static func fields(for moment: Moment) -> [String: Any] {
        var fields: [String: Any] = [
            "type": moment.type.rawValue,
            "occurredOn": moment.occurredOn,
            "renderedTextSnapshot": moment.renderedTextSnapshot,
            "accessibilityTextSnapshot": moment.accessibilityTextSnapshot,
            "localeIdentifier": moment.localeIdentifier,
            "copyDeckVersion": moment.copyDeckVersion,
            "schemaVersion": Moment.schemaVersion,
            "createdAt": Timestamp(date: moment.createdAt),
        ]
        if let petName = moment.petNameSnapshot {
            fields["petNameSnapshot"] = petName
        }
        if let subjectName = moment.subjectNameSnapshot {
            fields["subjectNameSnapshot"] = subjectName
        }
        if let sourceEventId = moment.sourceEventId {
            fields["sourceEventId"] = sourceEventId
        }
        return fields
    }

    static func moment(id: String, data: [String: Any]) -> Moment? {
        guard let typeRaw = data["type"] as? String,
              let type = MomentType(rawValue: typeRaw),
              let occurredOn = data["occurredOn"] as? String,
              let rendered = data["renderedTextSnapshot"] as? String
        else { return nil }
        return Moment(
            id: id,
            type: type,
            occurredOn: occurredOn,
            renderedTextSnapshot: rendered,
            accessibilityTextSnapshot: data["accessibilityTextSnapshot"] as? String ?? rendered,
            petNameSnapshot: data["petNameSnapshot"] as? String,
            subjectNameSnapshot: data["subjectNameSnapshot"] as? String,
            localeIdentifier: data["localeIdentifier"] as? String ?? "",
            copyDeckVersion: data["copyDeckVersion"] as? Int ?? 1,
            sourceEventId: data["sourceEventId"] as? String,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast
        )
    }
}

final class FirestoreMomentRepository: MomentRepository {

    private let firestore: Firestore

    init(firestore: Firestore) {
        self.firestore = firestore
    }

    private func collection(_ userId: String) -> CollectionReference {
        firestore.collection("users").document(userId).collection("moments")
    }

    func moments(userId: String) async throws -> [Moment] {
        FirestoreReadLog.record(Self.self)
        let snapshot = try await collection(userId)
            .order(by: "occurredOn", descending: true)
            .getDocuments()
        return snapshot.documents.compactMap { MomentFields.moment(id: $0.documentID, data: $0.data()) }
    }

    func ensureMoment(_ moment: Moment, userId: String) async {
        // Blind create, no read-before-write: the id is a natural key and
        // the rules are create-only, so a duplicate is rejected free of
        // charge (rejected writes are not billed; the existence check paid
        // a billed read on every attempt). Payloads for the same id are
        // deterministic aside from createdAt, and nothing user-visible
        // orders by createdAt, so the transient optimistic apply before a
        // rejection is invisible.
        FirestoreReadLog.recordWrite(Self.self)
        collection(userId).document(moment.id).setData(
            MomentFields.fields(for: moment), completion: nil
        )
    }
}
