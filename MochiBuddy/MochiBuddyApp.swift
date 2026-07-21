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

    @State private var container: AppContainer?

    init() {
        FirebaseApp.configure()
        // A reminders app must work offline.
        let settings = Firestore.firestore().settings
        settings.cacheSettings = PersistentCacheSettings()
        Firestore.firestore().settings = settings

        RevenueCatConfig.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    RootView(container: container)
                        .onOpenURL { url in
                            GIDSignIn.sharedInstance.handle(url)
                        }
                } else {
                    // A frame of brand background while last session's
                    // fetched tuning activates. The container - and so
                    // every engine - only exists after apply, keeping
                    // mood(t) deterministic for the whole session (the
                    // background fetch inside lands next launch).
                    MochiTheme.sesame.bg.ignoresSafeArea()
                }
            }
            .task {
                guard container == nil else { return }
                await RemoteTuning.bootstrap()
                container = AppContainer()
            }
        }
    }
}
