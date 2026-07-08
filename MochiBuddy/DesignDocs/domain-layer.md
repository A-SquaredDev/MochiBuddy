# Domain Layer — Stores

> Part of [App Architecture](app-architecture.md)

The Domain Layer sits between the Data Layer (repositories) and the Presentation Layer (ViewModels). Its primary building block is the **Store**—an entity that consumes one or more repositories to apply business logic, hold shared state, and emit events when data changes.

---

## What is a Store?

A Store is responsible for:

- **Aggregating data** from multiple repositories into complete domain models.
- **Holding shared state** that must be accessible from multiple screens or features.
- **Emitting events** so consumers (ViewModels, other stores) react to data changes.
- **Encapsulating business logic** that is not bound to a specific UI screen.

A Store is always **injected** and never a singleton.

---

## When to Create a Store

| Signal | Explanation |
|--------|-------------|
| Growing ViewModel complexity | If a ViewModel accumulates model-handling code mixed with presentation logic, extract a Store. |
| Complex business rules | Multiple repositories, branching async decisions, or multi-step operations belong in a Store. |
| Shared state across screens | When the same model must be available and mutable in multiple places. |
| Event-driven updates | Consumers need to react when data changes without polling. |

If a ViewModel only fetches from a single repository with no sharing or aggregation needs, use the repository directly—no Store required.

---

## Store Patterns

### 1. Event-Driven Store with Repository Aggregation

Provides domain data, emits typed events, and is consumed by one or more ViewModels.

```swift
// AccountsStore (Accounts module)

public enum AccountsStoreEvent {
    case accountsLoaded(AccountsCollection)
    case primaryAccountChanged(Account)
    case failedToLoadAccounts(Error)
}

public protocol AccountsStore {
    var events: AnyPublisher<AccountsStoreEvent, Never> { get }

    func accounts() async -> AccountsCollection
    @discardableResult
    func reloadAccounts() async throws -> AccountsCollection
    func reset()
    func setActive(accountId: UInt) async throws
    func setPrimary(accountId: UInt) async throws
    func removeAccount(accountId: UInt) async throws
}
```

**Key traits:**
- Exposes an `events` publisher for reactive consumers.
- Wraps async operations with `throws`—no optional results.
- Owns caching logic internally (callers are unaware of caching strategy).
- Provides an `AccountsCollection` protocol for immutable data access.

---

### 2. Actor-Based Store with Streaming

Uses Swift `actor` isolation for safe concurrent access and consumes an async stream to rebuild state.

```swift
// MenuTreeStore (App)

protocol MenuTreeStore {
    func buildMenu(with policy: MenuFetchPolicy) async throws
    func refreshMenu() async throws
    func getMenuTree() async -> MenuTree
    func getTreePublisher() async -> any Publisher<MenuTree, Never>
    func onSignout() async
}

actor MenuTreeStoreImpl: MenuTreeStore {
    private var currentTree: MenuTree {
        didSet { treeSubject.send(currentTree) }
    }
    private let treeSubject: CurrentValueSubject<MenuTree, Never>
    private let streamer: MenuStreaming

    func buildMenu(with policy: MenuFetchPolicy) async throws {
        await streamer.start(with: policy)
        streamTask = Task { [weak self, streamer] in
            for await event in streamer.stream {
                await self?.handle(event)
            }
        }
    }
}
```

**Key traits:**
- `actor` guarantees thread-safe state mutation without manual locking.
- Consumes an `AsyncSequence` stream to react to incremental updates.
- Publishes the current tree via `CurrentValueSubject` for reactive UI binding.
- Exposes lifecycle methods (`onSignout`) for cleanup.

---

### 3. Store as Single Source of Truth

Holds all data related to a feature, coordinates fetching, editing, and event broadcasting.

```swift
// ContentDataStore (Content module)

enum ContentDataStoreEvent: Equatable {
    case idle
    case loading
    case updated(ContentDataSource)
    case loaded
    case errorLoadingContent
}

protocol ContentDataStore {
    var contentDataSource: ContentDataSource { get }
    var events: AnyPublisher<ContentDataStoreEvent, Never> { get }

    func updateDataSource(contentDataSource: ContentDataSource)
    func reloadContent()
    func editContent(data: ArticleData,
                     editedData: MutableArticleData,
                     settings: SaveSettings?) async throws
}
```

**Key traits:**
- Owns the canonical `contentDataSource`—ViewModels read from it, never independently.
- Coordinates multi-repository fetching (data, details, categories).
- Broadcasting edits ensures all screens show consistent data.

---

### 4. Store with Comments & Pagination

Manages paginated data loading, user interactions, and broadcasts results as events.

```swift
// CommentDataStore (Comments module)

enum CommentStoreEvent {
    case startLoading
    case updateComments([CommentData], forceRefresh: Bool)
    case commentPost(CommentData)
    case updateComment(CommentData)
    case error(CommentsError)
}

protocol CommentDataStore {
    var events: AnyPublisher<CommentStoreEvent, Never> { get async }

    func fetchComments() async
    func refreshComments() async
    func fetchNextComments() async
    func postComment(_ text: AttributedString) async
    func deleteComment(_ comment: CommentData) async -> Bool
    func likeUnlikeComment(_ comment: CommentData) async throws
}
```

**Key traits:**
- Encapsulates pagination logic—ViewModels simply call `fetchNextComments()`.
- Combines data from multiple sources (comments, user profiles, profile images).
- Multiple ViewModels (comment list, tag user list, comment container) share the same store instance.

---

### 5. Observable Sync State

Tracks real-time state of sync operations and exposes an observable for UI binding.

```swift
// SyncStore (App)

enum SyncStoreState: Equatable {
    case idle
    case syncing
    case singleError
    case multipleErrors
}

protocol SyncStore {
    var syncState: Dynamic<SyncStoreState> { get }
    func isSyncing(itemId: UInt) -> Bool
    @discardableResult
    func syncItem(itemId: UInt) async throws -> SyncRequestResult
}
```

**Key traits:**
- Observable state (`Dynamic<T>`) drives UI without the UI knowing sync internals.
- Aggregates state from multiple items into a single unified status.
- Handles low-level transfer listener callbacks and maps them to domain events.

---

## Sharing Data Between Screens

For multi-screen flows that operate on the same mutable model (e.g. a creation/editing wizard), a **shared data object** can be injected into multiple ViewModels. This avoids the overhead of a full Store when:

- The data is not persisted or globally relevant.
- The flow is scoped to a navigation stack that is created and torn down together.

```swift
// CreateEditRecord.SharedRecordData (create/edit flow)

final class SharedRecordData {
    let record: CurrentValueSubject<Record, Never>
    let showMaxUseError: CurrentValueSubject<Bool, Never> = .init(false)
    let creatingNewRecord: Bool

    var thresholdChanges: AnyPublisher<Record, Never> {
        record.removeDuplicates { old, new in
            old.maxUsageDistanceMeters == new.maxUsageDistanceMeters &&
            old.maxUsageDurationSeconds == new.maxUsageDurationSeconds &&
            old.maxUsageDate == new.maxUsageDate
        }.eraseToAnyPublisher()
    }
}
```

**Usage pattern:**
- The Router (or Module) creates `SharedRecordData` and injects it into all ViewModels participating in the flow.
- `CurrentValueSubject` allows each screen to both read and write the shared model.
- Filtered publishers (e.g. `thresholdChanges`) let specific ViewModels react only to relevant mutations.
- When the flow completes (navigation stack is dismissed), the shared data is deallocated naturally.

---

## Guidelines

- **Always inject stores**—never use singletons or static access.
- **Define events as enums**—typed events make subscriptions explicit and testable.
- **Use `actor` for stores with complex concurrent state**—avoid manual locking.
- **A store never owns UI logic**—it works with domain models, not formatted strings or view state.
- **Repositories don't have events**—if you need events, you need a Store.
- **Prefer `async/await` with `throws`** for store APIs. Use Combine publishers only for event streams, not for request/response flows.
- **For scoped screen-sharing**, use a shared data object injected by the Router instead of a full Store.

---

## Reference

- [App Architecture](app-architecture.md)
- [Data Layer](data-layer.md)
