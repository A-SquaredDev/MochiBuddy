//
//  BillingNoticeRecorder.swift
//  MochiBuddy
//
//  users/{uid}/billingNotices/{noticeId} - the audit trail behind the
//  trial-ending notifications. One create-only document per scheduled
//  notice (the notice's notification id is the natural key), then
//  deliveryConfirmedAt is the ONE mutable field, written best-effort when
//  iOS shows us the notice actually fired. The record says "scheduled"
//  and "delivery confirmed", never "user was notified" - iOS offers no
//  delivery receipt for local notifications, and the trail must not claim
//  more than the platform can prove.
//

import Foundation
import FirebaseFirestore
import UserNotifications

protocol BillingNoticeRecording: AnyObject {
    /// Fire-and-forget audit write for a freshly scheduled trial notice.
    func recordScheduled(_ planned: PlannedNotification, trialEndsAt: Date) async
    /// Best-effort delivery confirmation for notices iOS reports as fired.
    func confirmDelivered(ids: [String])
}

final class FirestoreBillingNoticeRecorder: BillingNoticeRecording {

    private enum Key {
        static func confirmed(_ userId: String) -> String {
            "mochi.billing.confirmed.\(userId)"
        }
    }

    private let authRepository: AuthRepository
    private let permissionService: NotificationPermissionService
    private let firestore: Firestore
    private let defaults: UserDefaults

    init(
        authRepository: AuthRepository,
        permissionService: NotificationPermissionService,
        firestore: Firestore,
        defaults: UserDefaults = .standard
    ) {
        self.authRepository = authRepository
        self.permissionService = permissionService
        self.firestore = firestore
        self.defaults = defaults
    }

    private func collection(_ userId: String) -> CollectionReference {
        firestore.collection("users").document(userId).collection("billingNotices")
    }

    func recordScheduled(_ planned: PlannedNotification, trialEndsAt: Date) async {
        guard let userId = authRepository.currentAccount?.uid else { return }
        // The permission state at scheduling time is the single most
        // useful support fact: "we scheduled it, and notifications were
        // denied" answers the angry email honestly.
        let status = await permissionService.authorizationStatus()
        // Blind create, no read-before-write (the moments discipline):
        // the id is a natural key and the rules are create-only, so a
        // re-lay after reinstall is rejected free of charge.
        FirestoreReadLog.recordWrite(Self.self)
        collection(userId).document(planned.id).setData([
            "stage": NotificationID.parseTrialStage(planned.id)?.rawValue ?? "unknown",
            "fireAt": Timestamp(date: planned.fireAt),
            "trialEndsAt": Timestamp(date: trialEndsAt),
            "scheduledAt": FieldValue.serverTimestamp(),
            "authorizationStatusAtScheduling": Self.describe(status),
            "timeZone": TimeZone.current.identifier,
            "schemaVersion": 1,
        ], completion: nil)
    }

    func confirmDelivered(ids: [String]) {
        guard let userId = authRepository.currentAccount?.uid else { return }
        let key = Key.confirmed(userId)
        let already = Set(defaults.stringArray(forKey: key) ?? [])
        let fresh = ids.filter { $0.hasPrefix(NotificationID.trialPrefix) && !already.contains($0) }
        guard !fresh.isEmpty else { return }
        for id in fresh {
            FirestoreReadLog.recordWrite(Self.self)
            collection(userId).document(id).updateData([
                "deliveryConfirmedAt": FieldValue.serverTimestamp(),
            ]) { [defaults] error in
                guard error == nil else { return }
                var confirmed = Set(defaults.stringArray(forKey: key) ?? [])
                confirmed.insert(id)
                defaults.set(Array(confirmed), forKey: key)
            }
        }
    }

    private static func describe(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "notDetermined"
        case .denied: "denied"
        case .authorized: "authorized"
        case .provisional: "provisional"
        case .ephemeral: "ephemeral"
        @unknown default: "unknown"
        }
    }
}
