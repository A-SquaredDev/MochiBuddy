//
//  TestSupport.swift
//  MochiBuddyTests
//
//  Shared fixtures and capturing stubs for the domain protocols.
//

import Foundation
import Combine
@testable import MochiBuddy

struct TestError: Error, Equatable {}

/// Shared ordered log so tests can assert call ORDER across stubs
/// (e.g. "erase Firestore data strictly before deleting the Auth user").
final class CallLog {
    private(set) var entries: [String] = []
    func record(_ entry: String) { entries.append(entry) }
}

/// Collects one-shot NavigationEvents. `drain()` hops the main queue once so
/// events published via receive(on: .main) are delivered before asserting.
@MainActor
final class EventRecorder<Event> {
    private(set) var events: [Event] = []
    private var cancellable: AnyCancellable?

    init<S, A>(_ viewModel: ObservableStateViewModel<S, A, Event>) {
        cancellable = viewModel.navigationEvents.sink { [weak self] in
            self?.events.append($0)
        }
    }

    func drain() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

// MARK: - Date fixtures

enum Dates {
    static let calendar = Calendar.current

    /// A fixed anchor: Wed 8 Jul 2026, 10:00 local. Weekday-sensitive tests
    /// (weekday repeats) rely on Jul 10 being a Friday.
    static let now: Date = calendar.date(
        from: DateComponents(year: 2026, month: 7, day: 8, hour: 10, minute: 0)
    )!

    static func hours(_ h: Double, from base: Date = now) -> Date {
        base.addingTimeInterval(h * 3600)
    }

    static func days(_ d: Int, from base: Date = now) -> Date {
        calendar.date(byAdding: .day, value: d, to: base)!
    }

    static var startOfToday: Date { calendar.startOfDay(for: now) }
}

// MARK: - Model fixtures

func makeTask(
    id: String = UUID().uuidString,
    title: String = "Task",
    notes: String? = nil,
    dueAt: Date? = nil,
    hasTime: Bool = false,
    priority: TaskPriority = .med,
    listId: String? = nil,
    repeatRule: TaskRepeat? = nil,
    completed: Bool = false,
    completedAt: Date? = nil,
    createdAt: Date? = Dates.now
) -> TaskItem {
    TaskItem(
        id: id, title: title, notes: notes, dueAt: dueAt, hasTime: hasTime,
        priority: priority, listId: listId, repeatRule: repeatRule,
        completed: completed, completedAt: completedAt, createdAt: createdAt
    )
}

func makeProfile(
    coins: Int = 0,
    streak: Int = 0,
    bestStreak: Int = 0,
    lastActiveDate: Date? = nil,
    vacationMode: Bool = false
) -> UserProfile {
    UserProfile(
        id: "user1", displayName: "Alex Rivera", authProvider: nil, createdAt: nil,
        timezone: nil, bedtime: .standard, themeId: nil,
        coins: coins, streakCount: streak, bestStreakCount: bestStreak,
        lastActiveDate: lastActiveDate, isSubscribed: false, trialEndsAt: nil,
        onboardingComplete: true, notificationsEnabled: nil,
        notificationPrefs: .standard, soundEnabled: false,
        vacationMode: vacationMode, vacationResumeAt: nil,
        importedReminderListIds: []
    )
}

// MARK: - Stubs

final class StubAuthRepository: AuthRepository {
    var currentAccount: AuthAccount? = AuthAccount(
        uid: "user1", isAnonymous: false, displayName: "Alex Rivera",
        email: "alex@hey.com", providerId: "apple.com"
    )

    var ensureSessionError: Error?
    /// Result of a provider sign-in — may be a DIFFERENT account than the
    /// current one (credential already belonged to an existing user).
    var signInResult: AuthAccount?
    var appleSignInError: Error?
    var googleSignInError: Error?
    var reauthAppleError: Error?
    var reauthGoogleError: Error?
    var deleteError: Error?
    var nonce = AppleSignInNonce(raw: "raw-nonce", sha256: "hashed-nonce")
    var callLog: CallLog?

    private(set) var makeNonceCount = 0
    private(set) var appleSignIns: [(idToken: String, rawNonce: String, fullName: PersonNameComponents?)] = []
    private(set) var googleSignInCount = 0
    private(set) var appleReauths: [(idToken: String, rawNonce: String)] = []
    private(set) var googleReauthCount = 0
    private(set) var deleteCurrentUserCount = 0
    private(set) var signOutCount = 0

    func ensureSession() async throws -> AuthAccount {
        if let ensureSessionError { throw ensureSessionError }
        guard let currentAccount else { throw AuthRepositoryError.noActiveSession }
        return currentAccount
    }

    func makeAppleNonce() -> AppleSignInNonce {
        makeNonceCount += 1
        return nonce
    }

    func completeAppleSignIn(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws -> AuthAccount {
        appleSignIns.append((idToken, rawNonce, fullName))
        if let appleSignInError { throw appleSignInError }
        if let signInResult { return signInResult }
        return try await ensureSession()
    }

    func signInWithGoogle() async throws -> AuthAccount {
        googleSignInCount += 1
        if let googleSignInError { throw googleSignInError }
        if let signInResult { return signInResult }
        return try await ensureSession()
    }

    func signOut() throws { signOutCount += 1 }

    func reauthenticateWithApple(idToken: String, rawNonce: String) async throws {
        appleReauths.append((idToken, rawNonce))
        if let reauthAppleError { throw reauthAppleError }
    }

    func reauthenticateWithGoogle() async throws {
        googleReauthCount += 1
        if let reauthGoogleError { throw reauthGoogleError }
    }

    func deleteCurrentUser() async throws {
        if let deleteError { throw deleteError }
        deleteCurrentUserCount += 1
        callLog?.record("deleteAuthUser")
    }
}

final class StubMembershipStore: MembershipStore {
    var status: MembershipStatus = .notSubscribed
    var options: [MembershipPlanOption] = [.defaultYearly, .defaultMonthly]
    var restorable: RestorablePurchase?
    var purchaseError: Error?
    var restoreError: Error?

    private(set) var identifiedUserIds: [String] = []
    private(set) var startedTrials: [MembershipPlan] = []
    private(set) var restoredPurchases: [RestorablePurchase] = []

    func identify(userId: String) async { identifiedUserIds.append(userId) }
    func currentStatus() async -> MembershipStatus { status }
    func planOptions() async -> [MembershipPlanOption] { options }
    func restorablePurchase() async -> RestorablePurchase? { restorable }

    func startTrial(plan: MembershipPlan) async throws {
        if let purchaseError { throw purchaseError }
        startedTrials.append(plan)
        status = .trial(endsAt: Date.now.addingTimeInterval(7 * 24 * 3600))
    }

    func activate(plan: MembershipPlan) async throws {
        if let purchaseError { throw purchaseError }
        status = .active(plan: plan, renewsAt: nil)
    }

    func restore(_ purchase: RestorablePurchase) async throws {
        if let restoreError { throw restoreError }
        restoredPurchases.append(purchase)
        status = .active(plan: purchase.plan, renewsAt: purchase.renewsAt)
    }
}

final class StubAccountEraser: AccountEraser {
    var error: Error?
    var callLog: CallLog?
    private(set) var erasedUserIds: [String] = []

    func eraseAllData(userId: String) async throws {
        if let error { throw error }
        erasedUserIds.append(userId)
        callLog?.record("eraseData")
    }
}

final class StubProfileRepository: UserProfileRepository {
    var profile: UserProfile? = makeProfile()
    var fetchError: Error?
    private(set) var coinDeltas: [Int] = []
    private(set) var savedStreaks: [(count: Int, best: Int, lastActiveDate: Date)] = []
    private(set) var accountLinks: [(provider: String, displayName: String?, userId: String)] = []
    private(set) var membershipMirrors: [(isSubscribed: Bool, trialEndsAt: Date?, userId: String)] = []
    private(set) var ensuredAccounts: [AuthAccount] = []

    func fetchProfile(userId: String) async throws -> UserProfile? {
        if let fetchError { throw fetchError }
        return profile
    }
    func ensureProfile(for account: AuthAccount) async throws { ensuredAccounts.append(account) }
    func saveThemeId(_ themeId: String, userId: String) async throws {}
    func saveBedtime(_ bedtime: BedtimeWindow, userId: String) async throws {}
    func saveNotificationChoice(_ enabled: Bool, userId: String) async throws {}
    func saveNotificationPrefs(_ prefs: NotificationPrefs, userId: String) async throws {}
    func saveSoundEnabled(_ enabled: Bool, userId: String) async throws {}
    func saveVacation(mode: Bool, resumeAt: Date?, userId: String) async throws {}
    func saveImportedReminderLists(_ ids: [String], userId: String) async throws {}
    func saveAccountLink(provider: String, displayName: String?, userId: String) async throws {
        accountLinks.append((provider, displayName, userId))
    }
    func saveMembershipMirror(isSubscribed: Bool, trialEndsAt: Date?, userId: String) async throws {
        membershipMirrors.append((isSubscribed, trialEndsAt, userId))
    }
    func markOnboardingComplete(userId: String) async throws {}

    func incrementCoins(by delta: Int, userId: String) async throws {
        coinDeltas.append(delta)
        if var profile {
            profile.coins += delta
            self.profile = profile
        }
    }

    func saveStreak(count: Int, best: Int, lastActiveDate: Date, userId: String) async throws {
        savedStreaks.append((count, best, lastActiveDate))
        if var profile {
            profile.streakCount = count
            profile.bestStreakCount = best
            profile.lastActiveDate = lastActiveDate
            self.profile = profile
        }
    }
}

final class StubTaskRepository: TaskRepository {
    var incomplete: [TaskItem] = []
    var completed: [TaskItem] = []
    var completedStats: [CompletedTaskStat] = []
    var nextAddedTaskId = "added-task-id"

    private(set) var addedDrafts: [TaskDraft] = []
    private(set) var setCompletedCalls: [(taskId: String, completed: Bool)] = []
    private(set) var updatedTasks: [TaskItem] = []
    private(set) var snoozeCalls: [(id: String, newDueAt: Date)] = []
    private(set) var deletedIds: [String] = []

    @discardableResult
    func addTask(_ draft: TaskDraft, userId: String) async throws -> String {
        addedDrafts.append(draft)
        return nextAddedTaskId
    }
    func incompleteTasks(userId: String) async throws -> [TaskItem] { incomplete }
    func completedTasks(limit: Int, userId: String) async throws -> [TaskItem] { completed }
    func setCompleted(taskId: String, completed: Bool, userId: String) async throws {
        setCompletedCalls.append((taskId, completed))
    }
    func updateTask(_ task: TaskItem, userId: String) async throws { updatedTasks.append(task) }
    func snoozeTask(id: String, to newDueAt: Date, userId: String) async throws {
        snoozeCalls.append((id, newDueAt))
    }
    func deleteTask(id: String, userId: String) async throws { deletedIds.append(id) }
    func incompleteTaskCount(userId: String) async throws -> Int { incomplete.count }
    func totalTaskCount(userId: String) async throws -> Int { incomplete.count + completed.count }
    func completedTaskStats(since: Date, userId: String) async throws -> [CompletedTaskStat] {
        completedStats.filter { $0.completedAt >= since }
    }
}

final class StubListRepository: ListRepository {
    var lists: [TaskList] = []
    private(set) var createdNames: [String] = []

    func fetchLists(userId: String) async throws -> [TaskList] { lists }
    func createList(name: String, colorHex: String, icon: String, order: Int, userId: String) async throws {
        createdNames.append(name)
    }
    func renameList(id: String, name: String, userId: String) async throws {}
    func deleteList(id: String, userId: String) async throws {}
    func saveOrder(ids: [String], userId: String) async throws {}
}

final class StubComfortBufferStore: ComfortBufferStore {
    private(set) var boosts: [(lift: Double, duration: TimeInterval)] = []
    var value: Double = 0

    func add(lift: Double, duration: TimeInterval) {
        boosts.append((lift, duration))
        value = min(MoodEngine.Constants.bufferCap, value + lift)
    }
    func currentValue(now: Date) -> Double { value }
}
