//
//  MochiBuddyApp.swift
//  MochiBuddy
//
//  Created by Aaron McKain on 7/1/26.
//

import SwiftUI
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn

@main
struct MochiBuddyApp: App {

    @State private var container: AppContainer

    init() {
        FirebaseApp.configure()
        // A reminders app must work offline.
        let settings = Firestore.firestore().settings
        settings.cacheSettings = PersistentCacheSettings()
        Firestore.firestore().settings = settings

        RevenueCatConfig.configure()

        let container = AppContainer()
        _container = State(initialValue: container)

        // Activate last session's fetched tuning before anything computes,
        // then re-lay in case a lay raced the (near-instant) activation.
        // The background fetch inside lands next launch - values never
        // change mid-session, so mood(t) stays deterministic.
        Task { @MainActor in
            await RemoteTuning.bootstrap()
            container.notificationOrchestrator.requestRelay(.remoteConfigFetch)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
