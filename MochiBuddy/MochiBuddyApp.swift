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

        _container = State(initialValue: AppContainer())
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
