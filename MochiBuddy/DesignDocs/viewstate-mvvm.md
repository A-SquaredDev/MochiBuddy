# ViewState MVVM

> Part of [App Architecture](app-architecture.md)
>
> Base class: `ObservableStateViewModel` from `CommonUI`.

---

## Core Values

1. **Embrace SwiftUI key values** — unidirectional flow, views render state, declarative UI.
2. **Reusability** — Views and ViewModels are decoupled enough to be reused anywhere. A view cannot be aware of its position in the navigation structure nor directly create other views.
3. **Consistency and standardization** — a formalized View–ViewModel relationship ensures maintainability, easy collaboration, and fast onboarding.
4. **Embracing change** — SOLID principles give each component a clear, limited role. Code changes have measurable impact, not an avalanche effect.

---

## The Pattern at a Glance

```
┌─────────────────────────────────────────────────┐
│                     View                        │
│  Renders UIState · Sends ViewAction             │
└──────────────────────┬──────────────────────────┘
                       │ trigger(action)
                       ▼
┌─────────────────────────────────────────────────┐
│           ObservableStateViewModel              │
│  UIState (output) · ViewAction (input)          │
│  NavigationEvent (one-shot navigation)          │
└──────────────────────┬──────────────────────────┘
                       │ uses
                       ▼
┌─────────────────────────────────────────────────┐
│         Repositories / Stores                   │
│         Domain Models                           │
└─────────────────────────────────────────────────┘
```

The interaction between View and ViewModel has exactly **two components**:

- **Output:** a `UIState` rendered by the View.
- **Input:** a finite set of `ViewAction` cases coming from the View.

---

## ObservableStateViewModel

The base class (requires iOS 17+) uses Swift's `@Observable` macro internally. It is generic over three types:

```swift
@MainActor
open class ObservableStateViewModel<UIState, ViewAction, NavigationEvent> { ... }
```

| Type Parameter | Role |
|----------------|------|
| `UIState` | Equatable value type (struct) containing everything the view needs to render. |
| `ViewAction` | Enum of user intents that drive state changes. |
| `NavigationEvent` | One-shot event for navigation requests. Use `NoNavigationEvent` when not needed. |

### Key API

| Method / Property | Purpose |
|-------------------|---------|
| `uiState` | Current UI state (read-only convenience). |
| `state` | The `@Observable` container observed by SwiftUI. |
| `trigger(_ action:)` | Dispatches an action from a synchronous context (creates a Task). |
| `triggerAsync(_ action:)` | **Override point.** Handles actions with async business logic. |
| `setUIState(_:)` | The only sanctioned way to mutate state from subclasses. |
| `setNavigationEvent(_:)` | Emits a one-shot navigation event (not retained). |
| `navigationEvents` | Combine publisher for navigation events. |
| `collectBinding(for:action:)` | Creates a two-way `Binding` mediated by the ViewModel. |
| `subscript(dynamicMember:)` | Forwards key-path access directly to `UIState` (write `vm.title` not `vm.uiState.title`). |

### Convenience Typealiases

```swift
// When no navigation events are needed:
typealias StateViewModel<UIState, ViewAction> = ObservableStateViewModel<UIState, ViewAction, NoNavigationEvent>
```

---

## UIState

The `UIState` is a **struct** exposed by the ViewModel and observed by the View. It contains **all data needed by the view, already formatted**. It is a boundary model between the View and domain models.

### Design Rules

- Refer to titles, subtitles, flags—not `User.name` or `Article.wordCount`.
- Almost always includes a `Status` or relevant state flags defining the finite states of the view.
- Acts as a **blueprint of the feature**: reveals what data is displayed, what statuses exist, and what actions are available—without opening the View or ViewModel.

#### ⚠️ MANDATORY: Never expose domain models in UIState

`UIState` must **never** contain domain model types (e.g. `User`, `Article`, `Category`). Instead, define dedicated UI data structures (plain `struct`s) that hold only the data the view needs, already formatted as display-ready values (strings, booleans, URLs).

The ViewModel is responsible for mapping domain models → UI structs before calling `setUIState`.

##### ✅ Correct — dedicated UI struct with pre-formatted data

```swift
struct UserListUIItem: Equatable {
    let id: Int
    let fullName: String       // pre-formatted: "Janet Weaver"
    let email: String
    let avatarURL: URL?
}

struct UIState: UpdatableStruct, Equatable {
    var items: [UserListUIItem] = []
    var isLoading = false
    var error: String?
}

// In triggerAsync — map domain → UI struct:
let items = result.users.map {
    UserListUIItem(id: $0.id, fullName: $0.fullName, email: $0.email, avatarURL: $0.avatar)
}
setUIState(uiState.updating(\.items, to: items))
```

##### ❌ Forbidden — domain model leaked into UIState

```swift
// NEVER do this. Domain models must not appear in UIState.
struct UIState: UpdatableStruct {
    var users: [User] = []   // ❌ User is a domain model
}
```

> **Rule for code-generation agents:** Never place domain model types inside `UIState`. Always
> define a dedicated UI data struct (e.g. `UserListUIItem`) with display-ready properties and
> map from the domain model in `triggerAsync` before calling `setUIState`. Any UIState that
> contains a domain model type is non-compliant and must be refactored.

### UpdatableStruct Protocol

UIState structs conform to `UpdatableStruct` for ergonomic chained mutations:

```swift
struct UIState: UpdatableStruct {
    var title: String
    var isLoading: Bool
    var showError: Bool
}

// Usage in triggerAsync:
setUIState(
    uiState
        .updating(\.isLoading, to: true)
        .updating(\.showError, to: false)
)
```

### Two Valid Structures

| Approach | When to use |
|----------|-------------|
| **Struct with properties + Status enum** | Data must persist across statuses (e.g. during refresh or error). |
| **Enum with associated values per state** | View is structured around a `switch` over states. |

### Example

```swift
// CreateEditRecordBehavior.swift
enum CreateEditRecordBehavior {
    struct UIState: UpdatableStruct {
        let isEdit: Bool
        let recordUUID: String?
        var nickname: String
        var recordType: RecordType
        var firstUseDate: Date
        var selectedCategories: [ArticleCategory]
        var isSaving: Bool
        var showNicknameError: Bool
        var showSavingError: Bool
        // ...
    }
}
```

---

## ViewAction

A `ViewAction` is an enum defining every user intent that the View can communicate to the ViewModel:

```swift
enum Action {
    case load
    case saveTapped
    case didEnterNewValue(field: Field, newValue: String)
    case changeRecordType(recordType: RecordType)
    case confirmChangeRecordType
    case dismissSavingError
    // ...
}
```

Actions are the **only** way a View communicates intent to the ViewModel.

---

## NavigationEvent

A one-shot value emitted when the ViewModel needs to request navigation. Events are **not retained**—stale state is impossible.

```swift
enum Navigation {
    case dismiss
    case dismissToNewRecord(record: RecordDetailsUIModel)
}
```

Consumed in the View via `.onReceive`:

```swift
.onReceive(viewModel.navigationEvents) { event in
    switch event {
    case .dismiss: dismiss()
    case .dismissToNewRecord(let record): router.showRecordDetails(record)
    }
}
```

---

## ⚠️ MANDATORY: Behavior File — Namespacing UIState, ViewAction, NavigationEvent

`UIState`, `ViewAction`, `NavigationEvent`, and all related UI sub-structs (e.g. list item models) **must** be defined together in a dedicated file named `<Screen>Behavior.swift`, inside a namespace `enum` with the same name.

### Rules

- The file is named `<Screen>Behavior.swift` (e.g. `UserListBehavior.swift`).
- The top-level container is a **caseless `enum`** (used purely as a namespace): `enum <Screen>Behavior`.
- `UIState`, `ViewAction`, `NavigationEvent` (if needed), and **all UI sub-structs** used by `UIState` live inside this enum.
- The ViewModel references these types via the namespace: `UserListBehavior.UIState`, `UserListBehavior.ViewAction`.
- **Never** define `UIState`, `ViewAction`, or UI sub-structs inline inside the ViewModel file.

### ✅ Correct — `UserListBehavior.swift`

```swift
// UserListBehavior.swift
enum UserListBehavior {

    struct UIItem: Equatable {
        let id: Int
        let fullName: String
        let email: String
        let avatarURL: URL?
    }

    struct UIState: UpdatableStruct, Equatable {
        var items: [UIItem] = []
        var isLoading = false
        var hasNextPage = true
        var error: String?
    }

    enum ViewAction {
        case onAppear
        case loadNextPage
    }

    // Only needed if the screen navigates:
    enum NavigationEvent {
        case showUserDetail(id: Int)
    }
}
```

The ViewModel then uses the namespace:

```swift
// UserListViewModel.swift
final class UserListViewModel: ObservableStateViewModel<
    UserListBehavior.UIState,
    UserListBehavior.ViewAction,
    UserListBehavior.NavigationEvent
> { ... }
```

### ❌ Forbidden — types defined inline in the ViewModel

```swift
// NEVER do this.
final class UserListViewModel: ObservableStateViewModel<...> {
    struct UIState: UpdatableStruct { ... }   // ❌ must be in Behavior file
    enum ViewAction { ... }                   // ❌ must be in Behavior file
}
```

> **Rule for code-generation agents:** Always create a `<Screen>Behavior.swift` file with a
> namespace `enum <Screen>Behavior` containing `UIState`, `ViewAction`, any `NavigationEvent`,
> and all UI sub-structs. Reference them from the ViewModel via the namespace. Never define
> these types inline in the ViewModel or View files.

---

## ViewModel Implementation

A concrete ViewModel subclasses `ObservableStateViewModel` and overrides `triggerAsync(_:)` (or `trigger(_:)` for synchronous-only logic):

```swift
final class CreateEditRecordViewModel: ObservableStateViewModel<CreateEditRecord.UIState, CreateEditRecord.Action, CreateEditRecord.Navigation> {

    private let recordStore: RecordStore

    init(recordStore: RecordStore, ...) {
        self.recordStore = recordStore
        let initialState = CreateEditRecord.UIState(...)
        super.init(initialState: initialState)
    }

    override func triggerAsync(_ action: CreateEditRecord.Action) async {
        switch action {
        case .load:
            setUIState(uiState.updating(\.isLoading, to: true))
            // ... fetch data ...
            setUIState(uiState.updating(\.isLoading, to: false))
        case .saveTapped:
            await save()
        case .dismissSavingError:
            setUIState(uiState.updating(\.showSavingError, to: false))
        // ...
        }
    }
}
```

**ViewModel responsibilities:**

- Store domain model data needed to build the UIState.
- Use repositories and stores (never DTOs or API services directly).
- Map domain models to UIState properties (use a Presenter helper for complex mapping that is reused across screens).

**ViewModel must not:**

- Know about navigation or screen position.
- Import SwiftUI (except for `Binding` helpers).
- Hold references to Views.
- Subscribe to events or publishers in `init` (see rule below).

### ⚠️ MANDATORY: No Subscriptions in `init` — Use a `.load` Action

ViewModels **must not** subscribe to Combine publishers, store events, or any reactive streams in `init`. All subscriptions must be set up in response to a `.load` (or equivalent) `ViewAction`, triggered by the View's `.onLoad` / `.task` modifier.

**Why:** SwiftUI may create **transient ViewModel instances** during view evaluation before settling on the final `@State` instance. Subscriptions started in `init` on these throwaway instances lead to duplicated work, retain cycles, or missed events on the real instance. Deferring subscriptions to `.load` guarantees they run exactly once on the instance the view actually uses.

##### ❌ Forbidden — subscribing in `init`

```swift
init(contentStore: ContentDataStore) {
    self.contentStore = contentStore
    super.init(initialState: .init())

    // ❌ May run on a transient instance that gets discarded
    contentStore.events
        .sink { [weak self] in self?.handleEvent($0) }
        .store(in: &cancellables)
}
```

##### ✅ Correct — subscribing in `.load` action

```swift
override func triggerAsync(_ action: Action) async {
    switch action {
    case .load:
        subscribeToStoreEvents()  // ✅ Runs once, on the real instance
        await fetchInitialData()
    // ...
    }
}

private func subscribeToStoreEvents() {
    contentStore.events
        .sink { [weak self] in self?.handleEvent($0) }
        .store(in: &cancellables)
}
```

> **Rule for code-generation agents:** Never place Combine subscriptions, event observations, or
> any side-effecting setup in a ViewModel's `init`. All such work must happen in the handler for
> a `.load` action (or equivalent first-trigger action) so it executes exactly once on the
> instance the View actually retains. Any ViewModel that subscribes to publishers or events in
> `init` is non-compliant and must be refactored.

---

## Source of Truth: Domain Model, Not UIState

The **domain model** owned by the ViewModel is the source of truth—**not** the UIState. The UIState is a derived, read-only projection of the domain model plus transient UI flags.

### What belongs where

| In the Domain Model (private properties) | In the UIState |
|------------------------------------------|----------------|
| The actual data being created/edited | Formatted display values derived from the domain model |
| Business state (e.g. the record being edited, the article data) | Transient UI flags: `showAlert`, `isLoading`, `showError` |
| Values that will be persisted or sent to an API | Computed presentation (e.g. formatted dates, localized strings) |

### Why this matters for editing flows

When a View dispatches an editing action (e.g. the user changes a name), the ViewModel must:

1. **Apply the change to the domain model** it owns.
2. **Rebuild the UIState** from the updated domain model.

This keeps the flow simple and predictable:

```swift
// ❌ Wrong: storing editable data only in UIState
override func triggerAsync(_ action: Action) async {
    case .didChangeName(let name):
        setUIState(uiState.updating(\.nickname, to: name))  // UIState becomes source of truth — fragile
}

// ✅ Correct: domain model is source of truth
override func triggerAsync(_ action: Action) async {
    case .didChangeName(let name):
        editingRecord.name = name                           // mutate domain model
        setUIState(buildUIState(from: editingRecord))       // derive UIState from it
}
```

### Benefits

- **Single source of truth** — the domain model is always up-to-date and ready to be saved/sent.
- **Simple UI updates** — after any edit, just re-derive UIState from the domain model. No manual synchronization between UIState fields and the "real" data.
- **Consistent saving** — when the user taps save, the domain model is already complete. No need to reverse-map UIState back into a domain model.
- **Validation and saving operate on domain data** — validation logic runs against the domain model directly, making it easy to reason about correctness. Saving sends the domain model as-is. There is no fragile reverse-mapping step from UI strings back to typed domain values.
- **Reduced bugs** — eliminates drift between what the UI shows and what would be persisted.

This is critically important and in full accordance with Unidirectional Data Flow (UDF): **Action → mutate domain model → derive UIState → render**. The domain model is the single authority for validation, persistence, and business rules.

### Transient UI state

Pure UI concerns (alerts, loading spinners, sheet visibility) have no domain model equivalent. These live directly in UIState and are toggled via `setUIState`:

```swift
case .dismissError:
    setUIState(uiState.updating(\.showError, to: false))
```

This is fine because these flags are ephemeral and never saved or shared.

> **Rule for code-generation agents:** When handling an editing `ViewAction` (e.g. the user changed
> a field value), **never** store the new value only in `UIState`. Always apply it to the domain
> model the ViewModel owns first, then derive the new `UIState` from that domain model by calling
> a helper such as `buildUIState(from: domainModel)`. `UIState` must always be a computed
> projection of the domain model — it is never the source of truth for editable data. Any
> ViewModel that mutates `UIState` directly to persist an edited value (without first updating the
> domain model) is non-compliant and must be refactored.

---

## View

The View observes the ViewModel's `UIState` via the `@State` property wrapper:

```swift
struct CreateEditRecordView: View {
    @State var viewModel: ObservableStateViewModel<CreateEditRecord.UIState, CreateEditRecord.Action, CreateEditRecord.Navigation>
    let router: RecordRouting

    var body: some View {
        VStack {
            TextField("Name", text: viewModel.collectBinding(for: \.nickname, action: { .didEnterNewValue(field: .nickname, newValue: $0) }))

            Button("Save") { viewModel.trigger(.saveTapped) }
        }
        .onLoad { viewModel.trigger(.load) }
        .onReceive(viewModel.navigationEvents) { event in
            // handle navigation
        }
    }
}
```

### ⚠️ MANDATORY: Use `onLoad` for One-Time View Lifecycle Actions

When a view needs to trigger an action **exactly once** in its lifetime (e.g. initial data fetch), use the `onLoad` modifier from **CommonUI** — not `onAppear`:

```swift
.onLoad { viewModel.trigger(.load) }
```

`onAppear` fires every time the view appears (e.g. returning from a pushed screen), which causes unwanted duplicate loads. `onLoad` fires only once when the view is first created.

Alternatively, a bare `.task` modifier (no `id:`) is also acceptable — it runs once when the view appears for the first time:

```swift
.task { await viewModel.triggerAsync(.load) }
```

| Modifier | Fires | Use for |
|----------|-------|---------|
| `.onLoad` (CommonUI) | Once per view lifetime | Triggering a `ViewAction` synchronously (creates its own Task internally) |
| `.task` (no `id:`) | Once per view lifetime | Awaiting an async action directly |
| `.onAppear` | Every appearance | Refreshing data on return, analytics pings |

> **Rule for code-generation agents:** For initial/one-time loading, always use `.onLoad { viewModel.trigger(.load) }`
> (from CommonUI) or `.task { await viewModel.triggerAsync(.load) }`. Never use `.onAppear` for
> one-time setup — it will re-fire when navigating back to the screen. Any view that uses
> `.onAppear` for initial data loading is non-compliant and must be refactored to use `.onLoad` or `.task`.

---

### ⚠️ MANDATORY: Views Must Reference the Base Class, Never the Concrete ViewModel

A View's `viewModel` property **must always** be typed as the generic `ObservableStateViewModel<UIState, ViewAction, NavigationEvent>` base class — **never** as the concrete implementation (e.g. `CreateEditRecordViewModel`).

This is the **only guarantee** that the Unidirectional Data Flow (UDF) is respected:

- The View can only interact with the ViewModel through the sanctioned API: `uiState` (read) and `trigger(_:)` (write).
- Referencing the concrete class would expose internal methods and properties, breaking encapsulation and the UDF contract.

ViewModels are **always injected** into the View (by the Router or a parent). A View **must never create its own ViewModel**.

##### ✅ Correct — typed as base class, injected externally

```swift
struct CreateEditRecordView: View {
    // ✅ Base class type — only the UDF API is accessible
    @State var viewModel: ObservableStateViewModel<CreateEditRecord.UIState, CreateEditRecord.Action, CreateEditRecord.Navigation>

    // ✅ Injected by the Router, never instantiated here
}
```

##### ❌ Forbidden — concrete type or self-created ViewModel

```swift
struct CreateEditRecordView: View {
    // ❌ Concrete type — leaks internal implementation, breaks UDF guarantee
    @State var viewModel: CreateEditRecordViewModel

    // ❌ Never create a ViewModel inside a View
    @State var viewModel = CreateEditRecordViewModel(recordStore: ...)
}
```

> **Rule for code-generation agents:** The `viewModel` property in every View **must** be typed as
> `ObservableStateViewModel<Behavior.UIState, Behavior.ViewAction, Behavior.NavigationEvent>`.
> Never use the concrete ViewModel class as the property type. ViewModels are always injected
> (by the Router or initializer); a View must never instantiate a ViewModel itself.
> Any View that references a concrete ViewModel type or constructs its own ViewModel is
> non-compliant and must be refactored.

**View responsibilities:**

- Define layout.
- Bind UIState properties to UI elements.
- Relay UI events to ViewModel via `trigger(_:)`.

**A View should not:**

- Contain presentation logic or decisions based on model data.
- Be aware of its position in the navigation stack.
- Create other screens (that's the Router's job).
- Reference the concrete ViewModel type.
- Instantiate its own ViewModel.

**A View can** have its own `@State` properties for purely view-specific state (e.g. scroll position, focus state) that has no relation to business logic.

---

## Navigation and Data Passing (Router)

Neither the View nor the ViewModel should know about navigation. The **Router** handles this.

**Router responsibilities:**

- Create and configure screens to navigate to.
- Handle data passing between screens.

```swift
struct UserListRouter {
    func profileView(id: Int) -> some View { ... }
    func createProfile() -> some View { ... }
}
```

The router is injected into the View and used in `NavigationLink` destinations or programmatic navigation.

**Data passing:**

- The router does not use the ViewModel directly. A dedicated `*DataPassing` protocol declares passed data properties.
- **Passing data backwards:** use `CurrentValueSubject<Data, Never>` shared between screens, or a delegate pattern.
- **Scoped store:** a store created at the feature level (not registered in the DI container) and injected by the Router into multiple ViewModels is also an excellent option. It provides event-driven reactive updates, encapsulates shared business logic, and is deallocated naturally when the navigation stack is dismissed. See [Domain Layer — Sharing Data Between Screens](domain-layer.md#sharing-data-between-screens).

---

## SwiftUI Previews

A `PreviewObservableStateViewModel` class is provided for previews—pass a static UIState snapshot:

```swift
#Preview {
    CreateEditRecordView(
        viewModel: PreviewObservableStateViewModel(
            initialState: CreateEditRecord.UIState(isEdit: false, ...)
        ),
        router: PreviewRouter()
    )
}
```

---

## Bindings via collectBinding

For SwiftUI controls that require two-way bindings (alerts, sheets, toggles), use `collectBinding` to mediate through the ViewModel:

```swift
// Alert dismissal
.alert("Error", isPresented: viewModel.collectBinding(for: \.showSavingError, action: .dismissSavingError))

// Value-based binding
TextField("Name", text: viewModel.collectBinding(for: \.nickname, action: { .didEnterNewValue(field: .nickname, newValue: $0) }))
```

This keeps the unidirectional flow intact—writes go through `trigger(_:)` and the ViewModel decides how to update state.

---

## Unit Testing

ViewModel tests are straightforward:

1. Create the ViewModel with stubbed dependencies.
2. Call `trigger(_:)` or `await triggerAsync(_:)`.
3. Assert the resulting `uiState` values.

```swift
@Test func saveTapped_withEmptyName_showsError() async {
    let vm = CreateEditRecordViewModel(recordStore: stubStore, ...)
    await vm.triggerAsync(.saveTapped)
    #expect(vm.uiState.showNicknameError == true)
}
```

---

## Design Decisions

**Why unidirectional flow?**
Easier to reason about. Two-way bindings can lead to complex, hard-to-trace state cycles. The `collectBinding` helper provides two-way binding ergonomics while keeping the ViewModel in control.

**Why not formalize ViewState into a fixed set of states?**
Not all screens reduce to a fixed set. A well-written enum doesn't need a `default` case. Forcing a common ViewState would violate SOLID principles.

**Why @Observable over ObservableObject?**
`@Observable` (iOS 17+) provides fine-grained observation—only properties actually read by a view trigger re-renders. No need for `@Published` annotations.

---

## Reference

- `ObservableStateViewModel` (from CommonUI)
- [App Architecture](app-architecture.md)
