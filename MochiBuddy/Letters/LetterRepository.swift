//
//  LetterRepository.swift
//  MochiBuddy
//
//  users/{uid}/letters and users/{uid}/activityWeeks (Personal Layer,
//  Feature 3). Reading the archive is cache-friendly like every other
//  read; FIRST COMPOSITION is the app's one deliberate exception to the
//  fire-and-forget convention: it flushes pending writes, reads server-
//  backed state, and creates inside a transaction with an existence
//  precondition - first composer wins, every other device reads.
//

import Foundation
import FirebaseFirestore

protocol LetterRepository: AnyObject {
    /// The archive, newest first. Cache-friendly.
    func letters(userId: String) async throws -> [Letter]
    /// Server-backed archive for the composition barrier.
    func lettersFromServer(userId: String) async throws -> [Letter]
    /// Transactional create with an existence precondition: returns the
    /// stored letter - ours if the create won, the winner's if it lost.
    func createLetterIfAbsent(_ letter: Letter, userId: String) async throws -> Letter
    /// `readAt` is the letter's ONE mutable field, synced across devices.
    func markRead(letterId: String, at readAt: Date, userId: String) async throws
    /// Create-only weekly engagement marker - the deterministic dormancy
    /// arbiter. Idempotent from the caller's perspective.
    func ensureActivityMarker(periodId: String, userId: String) async throws
    func hasActivityMarker(periodId: String, userId: String) async throws -> Bool
    func hasActivityMarkerFromServer(periodId: String, userId: String) async throws -> Bool
    /// The barrier's flush: local writes (widget drains included) must
    /// reach the server before composition reads it.
    func flushPendingWrites() async throws
}

final class FirestoreLetterRepository: LetterRepository {

    private let firestore: Firestore

    init(firestore: Firestore) {
        self.firestore = firestore
    }

    private func letters(_ userId: String) -> CollectionReference {
        firestore.collection("users").document(userId).collection("letters")
    }

    private func activityWeeks(_ userId: String) -> CollectionReference {
        firestore.collection("users").document(userId).collection("activityWeeks")
    }

    // MARK: - Archive

    func letters(userId: String) async throws -> [Letter] {
        try await letters(userId: userId, source: .default)
    }

    func lettersFromServer(userId: String) async throws -> [Letter] {
        try await letters(userId: userId, source: .server)
    }

    private func letters(userId: String, source: FirestoreSource) async throws -> [Letter] {
        FirestoreReadLog.record(Self.self)
        let snapshot = try await letters(userId)
            .order(by: "periodStart", descending: true)
            .getDocuments(source: source)
        return snapshot.documents.compactMap { Self.letter(id: $0.documentID, data: $0.data()) }
    }

    // MARK: - First composition

    func createLetterIfAbsent(_ letter: Letter, userId: String) async throws -> Letter {
        FirestoreReadLog.record(Self.self)
        FirestoreReadLog.recordWrite(Self.self)
        let reference = letters(userId).document(letter.id)
        let winnerData = try await firestore.runTransaction { transaction, errorPointer in
            do {
                let snapshot = try transaction.getDocument(reference)
                if snapshot.exists {
                    // Two devices raced Monday morning: the other one won.
                    // Discard ours, read theirs.
                    return snapshot.data()
                }
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            transaction.setData(Self.fields(for: letter), forDocument: reference)
            return nil
        }
        if let winnerData = winnerData as? [String: Any],
           let winner = Self.letter(id: letter.id, data: winnerData) {
            return winner
        }
        return letter
    }

    func markRead(letterId: String, at readAt: Date, userId: String) async throws {
        FirestoreReadLog.recordWrite(Self.self)
        // Fire-and-forget like every ordinary write; readAt is the one
        // field the rules leave mutable.
        letters(userId).document(letterId).setData(
            ["readAt": Timestamp(date: readAt)], merge: true, completion: nil
        )
    }

    // MARK: - Engagement marker

    func ensureActivityMarker(periodId: String, userId: String) async throws {
        guard try await !hasActivityMarker(periodId: periodId, userId: userId) else { return }
        FirestoreReadLog.recordWrite(Self.self)
        // Create-only by rules; a raced duplicate create is rejected
        // server-side and harmless (the content is the same fact).
        activityWeeks(userId).document(periodId).setData(
            ["firstSeenAt": FieldValue.serverTimestamp()], completion: nil
        )
    }

    func hasActivityMarker(periodId: String, userId: String) async throws -> Bool {
        FirestoreReadLog.record(Self.self)
        return try await activityWeeks(userId).document(periodId).getDocument().exists
    }

    func hasActivityMarkerFromServer(periodId: String, userId: String) async throws -> Bool {
        FirestoreReadLog.record(Self.self)
        return try await activityWeeks(userId).document(periodId).getDocument(source: .server).exists
    }

    func flushPendingWrites() async throws {
        try await firestore.waitForPendingWrites()
    }

    // MARK: - Mapping

    private static func fields(for letter: Letter) -> [String: Any] {
        var fields: [String: Any] = [
            "periodStart": Timestamp(date: letter.periodStart),
            "periodEndExclusive": Timestamp(date: letter.periodEndExclusive),
            "timeZone": letter.timeZoneId,
            "classification": letter.classification.rawValue,
            "beatTypes": letter.beatTypes.map(\.rawValue),
            "lineIds": letter.lineIds,
            "fullRenderedText": letter.fullRenderedText,
            "privateRenderedText": letter.privateRenderedText,
            "petNameSnapshot": letter.petNameSnapshot,
            "composedAt": Timestamp(date: letter.composedAt),
            "composerVersion": letter.composerVersion,
            "copyDeckVersion": letter.copyDeckVersion,
            "periodSummaryHash": letter.periodSummaryHash,
        ]
        if let readAt = letter.readAt {
            fields["readAt"] = Timestamp(date: readAt)
        }
        return fields
    }

    private static func letter(id: String, data: [String: Any]) -> Letter? {
        guard let periodStart = (data["periodStart"] as? Timestamp)?.dateValue(),
              let periodEnd = (data["periodEndExclusive"] as? Timestamp)?.dateValue(),
              let classification = LetterClassification(
                  rawValue: data["classification"] as? String ?? ""
              ),
              let fullText = data["fullRenderedText"] as? String,
              let privateText = data["privateRenderedText"] as? String
        else { return nil }
        return Letter(
            id: id,
            periodStart: periodStart,
            periodEndExclusive: periodEnd,
            timeZoneId: data["timeZone"] as? String ?? TimeZone.current.identifier,
            classification: classification,
            beatTypes: (data["beatTypes"] as? [String] ?? []).compactMap(LetterBeatType.init(rawValue:)),
            lineIds: data["lineIds"] as? [String] ?? [],
            fullRenderedText: fullText,
            privateRenderedText: privateText,
            petNameSnapshot: PetNameSanitizer.canonicalName(from: data["petNameSnapshot"] as? String),
            composedAt: (data["composedAt"] as? Timestamp)?.dateValue() ?? periodEnd,
            composerVersion: data["composerVersion"] as? Int ?? 0,
            copyDeckVersion: data["copyDeckVersion"] as? Int ?? 0,
            periodSummaryHash: data["periodSummaryHash"] as? String ?? "",
            readAt: (data["readAt"] as? Timestamp)?.dateValue()
        )
    }
}
