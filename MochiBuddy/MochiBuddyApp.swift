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

    /// The unit-test runner injects into this app via TEST_HOST, so the
    /// host process boots for every test run. Without this gate that boot
    /// reaches splash and mints a live anonymous Firebase user (plus its
    /// users/{uid} doc and a RevenueCat identity) against production, once
    /// per run on a fresh simulator. Under tests the container never
    /// builds and RevenueCat never configures; the host shows only the
    /// brand background frame. FirebaseApp.configure() still runs: it
    /// performs no sign-in and writes nothing, and RemoteTuningTests
    /// reads the (never-fetched) default RemoteConfig instance, which
    /// traps if the default app is absent.
    private static let isHostingUnitTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() {
        FirebaseApp.configure()
        // A reminders app must work offline.
        let settings = Firestore.firestore().settings
        settings.cacheSettings = PersistentCacheSettings()
        Firestore.firestore().settings = settings

        guard !Self.isHostingUnitTests else { return }
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
                guard container == nil, !Self.isHostingUnitTests else { return }
                await RemoteTuning.bootstrap()
                container = AppContainer()
            }
        }
    }
}
