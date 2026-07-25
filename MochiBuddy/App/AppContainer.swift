//
//  AppContainer.swift
//  MochiBuddy
//
//  Composition root - every dependency is created once here and injected
//  (no singleton access anywhere below this).
//

import FirebaseFirestore
import Foundation
import UIKit
import UserNotifications

@MainActor
final class AppContainer {

    let session = AppSession()
    // Home-screen icon follows the flavor. setAlternateIconName is flaky
    // around app activation: the system cancels it outright until the app
    // is active (NSCocoaErrorDomain 3072) and its alert-token machinery
    // returns transient EAGAIN (NSPOSIXErrorDomain 35) for a while right
    // after foregrounding, so wait for activation and retry patiently.
    // No alternateIconName-equality guard: a half-failed set can leave
    // LaunchServices recording a name SpringBoard never displayed, and the
    // guard would then skip forever. Same-name sets are a system no-op
    // (no alert), so always calling is safe.
    let themeStore = ThemeStore(syncAppIcon: { iconName in
        Task { @MainActor in
            for _ in 0..<50 where UIApplication.shared.applicationState != .active {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard UIApplication.shared.supportsAlternateIcons else { return }
            for attempt in 1...6 {
                do {
                    try await UIApplication.shared.setAlternateIconName(iconName)
                    return
                } catch where attempt < 6 {
                    try? await Task.sleep(for: .seconds(1))
                } catch {
                    // A stale icon beats a crash; log the why and move on.
                    NSLog("Icon sync to '%@' failed: %@", iconName ?? "primary", String(describing: error))
                }
            }
        }
    })

    let authRepository: AuthRepository
    let profileRepository: UserProfileRepository
    let taskRepository: TaskRepository
    let listRepository: ListRepository
    let accountEraser: AccountEraser
    let membershipStore: MembershipStore
    let membershipSession = MembershipSession()
    let notificationPermissionService: NotificationPermissionService
    let remindersGateway: RemindersGateway
    let comfortBufferStore: ComfortBufferStore
    let rewardsStore: RewardsStore
    let celebrationCenter = CelebrationCenter()
    let taskCompletionStore: TaskCompletionStore
    let recurrenceRoller: RecurrenceRoller
    let notificationScheduler: NotificationScheduling
    let notificationOrchestrator: NotificationOrchestrator
    let petIdentityStore: PetIdentityStore
    let observationIntervalRecorder: ObservationIntervalRecorder
    let observationLedger = ObservationLedger()
    let observationService: ObservationService
    let callbackLedger = CallbackLedger()
    let momentRepository: MomentRepository
    let momentWriter: MomentWriter
    let memoriesService: MemoriesService
    let suggestionLedger = SuggestionLedger()
    let suggestionService: SuggestionService
    /// Tab selection + the letter handoff into the Journal (Feature 6).
    let tabCoordinator = TabCoordinator(telemetry: OSLogJournalTelemetry())
    let letterRepository: LetterRepository
    let letterCompositionService: LetterCompositionService
    let vacationReentryService: VacationReentryService
    let widgetStateMirror: WidgetStateMirror
    let widgetCompletionDrain: WidgetCompletionDrain
    let notificationActionHandler: NotificationActionHandler
    /// Strong ref - UNUserNotificationCenter keeps its delegate weak.
    private let notificationDelegate = MochiNotificationDelegate()

    init() {
        let firestore = Firestore.firestore()
        authRepository = FirebaseAuthRepository()
        profileRepository = CachingUserProfileRepository(
            wrapping: FirestoreUserProfileRepository(firestore: firestore)
        )
        taskRepository = FirestoreTaskRepository(firestore: firestore)
        listRepository = FirestoreListRepository(firestore: firestore)
        accountEraser = FirestoreAccountEraser(firestore: firestore)
        // -mochiLocalMembership keeps membership device-local for UI work
        // without touching StoreKit/sandbox.
        membershipStore = ProcessInfo.processInfo.arguments.contains("-mochiLocalMembership")
            ? LocalMembershipStore()
            : RevenueCatMembershipStore()
        notificationPermissionService = UNNotificationPermissionService()
        remindersGateway = EventKitRemindersGateway()
        // The buffer lives in the App Group so the widget reads (and pets)
        // the same one - still device-local, never synced.
        let groupDefaults = MochiAppGroup.defaults
        UserDefaultsComfortBufferStore.migrateToAppGroup(to: groupDefaults)
        comfortBufferStore = UserDefaultsComfortBufferStore(defaults: groupDefaults)
        rewardsStore = RewardsStore(profileRepository: profileRepository)
        taskCompletionStore = TaskCompletionStore(
            taskRepository: taskRepository,
            rewardsStore: rewardsStore,
            membershipSession: membershipSession
        )
        recurrenceRoller = RecurrenceRoller(taskRepository: taskRepository)
        petIdentityStore = PetIdentityStore(
            profileRepository: profileRepository,
            telemetry: OSLogPetIdentityTelemetry()
        )
        // Feature 6: the Journal's synced moment records and their one
        // producer funnel (payload derivation stays in the pure factory).
        momentRepository = FirestoreMomentRepository(firestore: firestore)
        momentWriter = MomentWriter(
            authRepository: authRepository,
            momentRepository: momentRepository,
            petIdentityStore: petIdentityStore,
            listRepository: listRepository,
            membershipSession: membershipSession,
            calendar: .autoupdatingCurrent
        )

        let telemetry = OSLogNotificationTelemetry()
        notificationScheduler = UNNotificationScheduler()
        // Auto-updating: the orchestrator and mirror hold their calendar
        // for the app's lifetime, and timed reminders are wall-clock
        // intentions - a landed flight must re-lay against the NEW zone.
        notificationOrchestrator = NotificationOrchestrator(
            authRepository: authRepository,
            profileRepository: profileRepository,
            taskRepository: taskRepository,
            recurrenceRoller: recurrenceRoller,
            bufferStore: comfortBufferStore,
            membershipSession: membershipSession,
            scheduler: notificationScheduler,
            telemetry: telemetry,
            calendar: .autoupdatingCurrent
        )
        observationIntervalRecorder = ObservationIntervalRecorder(
            authRepository: authRepository,
            profileRepository: profileRepository
        )
        observationService = ObservationService(
            authRepository: authRepository,
            profileRepository: profileRepository,
            taskRepository: taskRepository,
            listRepository: listRepository,
            ledger: observationLedger,
            telemetry: OSLogObservationTelemetry()
        )
        // Feature 5: the editor's suggested-time chip - assembles a
        // session over the observation fetch, owns the dismissal ledger.
        suggestionService = SuggestionService(
            authRepository: authRepository,
            profileRepository: profileRepository,
            taskRepository: taskRepository,
            observationService: observationService,
            membershipSession: membershipSession,
            ledger: suggestionLedger,
            telemetry: OSLogSuggestionTelemetry(),
            calendar: .autoupdatingCurrent
        )
        memoriesService = MemoriesService(
            authRepository: authRepository,
            profileRepository: profileRepository,
            observationService: observationService,
            observationLedger: observationLedger,
            ledger: callbackLedger,
            membershipSession: membershipSession,
            celebrationCenter: celebrationCenter,
            momentWriter: momentWriter,
            telemetry: OSLogCallbackTelemetry(),
            calendar: .autoupdatingCurrent
        )
        // Feature 2: the one Personal-Layer line per rundown (canonical
        // priority incl. Feature 4's observation tier) is chosen and
        // cadence-committed by the memories service on every re-lay.
        notificationOrchestrator.personalLayerProvider = { [weak memoriesService] request in
            await memoriesService?.assignPersonalLayer(
                rundowns: request.rundowns,
                snapshot: request.snapshot,
                taper: request.taper,
                completionTimes: request.completionTimes,
                now: request.now
            ) ?? [:]
        }
        letterRepository = FirestoreLetterRepository(firestore: firestore)
        letterCompositionService = LetterCompositionService(
            authRepository: authRepository,
            profileRepository: profileRepository,
            taskRepository: taskRepository,
            listRepository: listRepository,
            letterRepository: letterRepository,
            observationLedger: observationLedger,
            membershipSession: membershipSession,
            relay: notificationOrchestrator,
            telemetry: OSLogLetterTelemetry()
        )
        // The scheduling invariant: the planner hears about a letter only
        // once its period is already non-dormant - the letter service owns
        // that judgment (it owns the marker).
        notificationOrchestrator.letterInputProvider = { [weak letterCompositionService] now in
            await letterCompositionService?.plannedLetterInput(now: now)
        }
        // A tapped invitation routes into the Journal's letter view via
        // the stable letter id (Feature 6's navigation-only handoff). The
        // coordinator holds the route until the tab shell is mounted.
        notificationDelegate.onLetterTap = { [weak tabCoordinator] letterId in
            tabCoordinator?.openLetterInJournal(letterId, source: .notification)
        }
        vacationReentryService = VacationReentryService(
            profileRepository: profileRepository,
            taskRepository: taskRepository,
            bufferStore: comfortBufferStore,
            relay: notificationOrchestrator,
            intervalRecorder: observationIntervalRecorder,
            momentWriter: momentWriter
        )
        notificationActionHandler = NotificationActionHandler(
            authRepository: authRepository,
            taskRepository: taskRepository,
            profileRepository: profileRepository,
            completionStore: taskCompletionStore,
            bufferStore: comfortBufferStore,
            orchestrator: notificationOrchestrator,
            telemetry: telemetry
        )
        notificationDelegate.actionHandler = notificationActionHandler
        UNUserNotificationCenter.current().delegate = notificationDelegate
        NotificationCategories.register()

        // PetIdentityDidChange, steps 2-3: action labels re-register
        // BEFORE the re-lay so newly laid notifications reference matching
        // labels; the re-lay rewrites mood pings + rundowns with the new
        // name (promises carry no name, by the locked rule). Step 4, the
        // widget mirror, rides the relay's onRelaid hook below.
        petIdentityStore.onIdentityChanged = { [weak notificationOrchestrator] name in
            NotificationCategories.register(petName: name)
            notificationOrchestrator?.requestRelay(.petIdentityChange)
        }
        // On every profile load, align labels with a name chosen in a past
        // session or on another device (cheap, idempotent).
        petIdentityStore.onLoaded = { name in
            NotificationCategories.register(petName: name)
        }

        // Every check-off (from any surface) re-lays the schedule.
        taskCompletionStore.onMutation = { [weak notificationOrchestrator] in
            notificationOrchestrator?.requestRelay(.taskChange)
        }
        // Milestones from any surface (incl. the widget drain) celebrate
        // in-app on Home - completions only happen with the app open or
        // land at drain time on the next open, so a push would always
        // arrive while the user is already looking at Mochi.
        taskCompletionStore.onMilestone = { [weak celebrationCenter, weak momentWriter] milestone in
            celebrationCenter?.post(milestone: milestone)
            // Journal record (Feature 6), at the crossing edge - a rebuilt
            // streak reaching the same count later is a NEW moment.
            Task { @MainActor in
                await momentWriter?.streakMilestone(count: milestone)
            }
        }
        // A lapse or reactivation reshapes the whole plan (promises-only
        // vs the full set) the moment it's learned - and lands in the
        // observation interval log (Feature 4: momentum eligibility).
        membershipSession.onChange = { [weak notificationOrchestrator, weak membershipSession,
                                        weak observationIntervalRecorder] in
            notificationOrchestrator?.requestRelay(.entitlementChange)
            guard let membershipSession else { return }
            let isLapsed = membershipSession.isLapsed
            Task { @MainActor in
                await observationIntervalRecorder?.membershipChanged(isLapsed: isLapsed)
            }
        }

        widgetStateMirror = WidgetStateMirror(themeStore: themeStore, calendar: .autoupdatingCurrent)
        widgetCompletionDrain = WidgetCompletionDrain(
            authRepository: authRepository,
            taskRepository: taskRepository,
            profileRepository: profileRepository,
            completionStore: taskCompletionStore
        )
        // Every lay refreshes the widget from the exact world it planned.
        notificationOrchestrator.onRelaid = { [weak widgetStateMirror] context in
            widgetStateMirror?.mirror(context: context)
        }
        // Timed reminders are wall-clock intentions ("5pm" fires at 5pm
        // wherever the user lands) - a timezone change re-lays everything
        // against the new local clock.
        NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main
        ) { [weak notificationOrchestrator] _ in
            Task { @MainActor in
                notificationOrchestrator?.requestRelay(.timezoneChange)
            }
        }

        // -mochiStartAtHome skips the flow for UI work on the tab surfaces
        // (pair with "-mochiStartTab you|tasks" to land on a specific tab).
        if ProcessInfo.processInfo.arguments.contains("-mochiStartAtHome") {
            session.phase = .home
        }
        // -mochiStartLapsed previews the degraded quiet-checklist mode.
        if ProcessInfo.processInfo.arguments.contains("-mochiStartLapsed") {
            membershipSession.status = .lapsed
        }
    }
}
