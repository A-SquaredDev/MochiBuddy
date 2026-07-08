# Routing

> Part of [App Architecture](app-architecture.md) · [ViewState MVVM](viewstate-mvvm.md)

---

## Core Principle

Neither the View nor the ViewModel should have any knowledge of navigation or the screen's position within the application. This is critical for:

- **Reusability** — Views and ViewModels can be placed anywhere in the navigation hierarchy.
- **Single Responsibility** — Navigation is a concern distinct from rendering (View) and business logic (ViewModel).

The **Router** is the dedicated component that owns navigation logic.

---

## Router Responsibilities

1. **Create and configure screens** — instantiate ViewModels with their dependencies, wire up Routers, and return fully configured Views.
2. **Handle data passing** between screens (forward and backward).
3. **Manage navigation transitions** — push, pop, replace stack, present sheets.

A Router does **not**:

- Contain business logic.
- Directly expose or reference ViewModel internals.
- Hold UI state.

---

## Architecture at a Glance

```
┌─────────────┐  trigger(.action)  ┌────────────────────┐
│    View     │ ──────────────────► │     ViewModel      │
│             │ ◄─────────────────  │ (ObservableState   │
│ renders     │     UIState         │  ViewModel)        │
│ uiState     │                     │                    │
│             │ ◄─ navigationEvents │                    │
└──────┬──────┘                     └────────────────────┘
       │
       │ .onReceive(viewModel.navigationEvents) { event in
       │     router.navigateTo...(event)
       │ }
       ▼
┌─────────────────────────────────────────────────────────┐
│                        Router                           │
│  • Creates ViewModels with dependencies                 │
│  • Creates child Routers                                │
│  • Calls NavController to push/pop/replace              │
│  • Returns configured Views for embedding               │
└─────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────┐
│                    NavController                         │
│  (Custom abstraction over UINavigationController)       │
│  navigateTo(route:) · navigate(view:) · popBackStack()  │
│  replaceStack(with:startingFrom:) · replaceLast(with:)  │
└─────────────────────────────────────────────────────────┘
```

---

## Defining a Routing Protocol

Each screen defines its own **Routing protocol** that declares all destinations reachable from that screen. This keeps the interface visible and testable.

```swift
@MainActor
protocol RecordRouting {
    func navigateToDetails(model: RecordDetailsUIModel, articleId: Int?)
    func navigateToCreateRecord(newRecordType: RecordType, resultNavBehavior: CreateEditRecord.ResultNavBehavior)
    func navigateToEditRecord(editRecord: Record)
    func navigateToRelatedArticles(recordInfo: RelatedArticles.RecordInfo)
    func navigateToArticle(_ id: Int)
}
```

**Naming convention:** `<Feature>Routing` for the protocol, `<Feature>Router` for the concrete implementation.

Methods either:
- **Trigger navigation** (side effect, returns `Void`) — e.g. `navigateToDetails(...)`.
- **Return a View** for embedding — e.g. `func cardView(for:) -> some View`.

---

## Implementing a Router

A Router is typically a `struct` or `class` that:
1. Holds a `NavController` (the navigation abstraction).
2. Holds dependencies needed to create child screens.
3. Conforms to the `*Routing` protocol.

### Simple Router (struct)

```swift
@MainActor
struct CreatePlanRouter: CreatePlanRouting {
    let navController: NavController
    let isMetricSystem: Bool
    let orientationLocker: OrientationLocker

    func start() -> AnyView {
        CreatePlanView(router: self)
            .orientationToPortrait(using: orientationLocker)
            .eraseToAnyView()
    }

    func navigateToSelectOption() {
        navController.navigate(
            view: SelectOptionView(
                router: self,
                selectedOption: nil,
                isMetric: isMetricSystem,
                editMode: false,
                onDismiss: nil
            )
            .orientationToPortrait(using: orientationLocker)
            .eraseToAnyView()
        )
    }

    func navigateToPlanDetails(selectedOption: PlanOption, time: Double, isMetric: Bool) {
        let route = PlanDetailsByOptionRoute(
            option: ...,
            optionValue: selectedOption.valueInMeters,
            goalTime: time,
            isMetric: isMetric
        )
        navController.replaceStack(
            with: [route],
            startingFrom: CreatePlanStrategyRoute.self,
            excludeStart: false,
            animated: true
        )
    }
}
```

### Complex Router (class with dependencies)

```swift
@MainActor
class RecordRouter: RecordRouting {
    private let dependencies: RecordFeatureBuilder.Dependencies
    private let navController: NavController

    init(dependencies: RecordFeatureBuilder.Dependencies, navController: NavController) {
        self.dependencies = dependencies
        self.navController = navController
    }

    func navigateToDetails(model: RecordDetailsUIModel, articleId: Int?) {
        navController.navigateTo(
            DetailsRoute(
                router: self,
                dependencies: RecordDetails.Dependencies(
                    recordStore: dependencies.resolver.instance(of: RecordStore.self),
                    reachability: dependencies.resolver.instance(of: ReachabilityStatusProvider.self),
                    activityIndicator: dependencies.activityIndicatorProvider,
                    measurementSystem: dependencies.resolver.instance(of: DistanceSettings.self).distanceUnitSystem
                ),
                model: model,
                articleId: articleId
            )
        )
    }

    func navigateToCreateRecord(newRecordType: RecordType, resultNavBehavior: CreateEditRecord.ResultNavBehavior) {
        let route = CreateEditRecordRoute(
            router: self,
            dependencies: createEditRecordDependencies(),
            editRecord: nil,
            newRecordType: newRecordType,
            resultNavBehavior: resultNavBehavior
        )
        navController.replaceStack(with: [route], startingFrom: SelectRecordTypeRoute.self, animated: true)
    }
}
```

---

## How the View Uses the Router

The Router is **injected** into the View. The View calls router methods in two scenarios:

### 1. Directly (for static navigation, e.g. toolbar buttons)

```swift
struct OffersListView: View {
    let router: any OffersRouting

    var body: some View {
        // ...
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Help") { router.navigate(to: .help) }
            }
        }
    }
}
```

### 2. Via NavigationEvent from ViewModel (for logic-driven navigation)

The ViewModel emits a one-shot `NavigationEvent` when business logic determines navigation should occur. The View subscribes and delegates to the Router:

```swift
struct RecordDetailsView: View {
    @State var viewModel: ObservableStateViewModel<RecordDetailsBehavior.UIState, RecordDetailsBehavior.ViewAction, RecordDetailsBehavior.NavigationEvent>
    let router: any RecordRouting

    var body: some View {
        // ...
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .showRelatedArticles(let recordInfo):
                router.navigateToRelatedArticles(recordInfo: recordInfo)
            case .showEditRecord(let record):
                router.navigateToEditRecord(editRecord: record)
            }
        }
    }
}
```

### 3. Embedding child views (Router returns a View)

```swift
struct FriendsView: View {
    let router: any FriendsRouting

    var body: some View {
        ForEach(viewModel.tabs, id: \.localizedTitle) { tab in
            router.startFriendList(tab, selectedTabIndex: $viewModel.displayEvent.selectedTab)
        }
    }
}
```

---

## NavController

`NavController` is the project's custom abstraction over `UINavigationController`. Routers use it to perform navigation operations.

### Key API

| Method | Purpose |
|--------|---------|
| `navigateTo(_ route: NavRoute)` | Push a registered route onto the navigation stack. |
| `navigate(view:)` | Push an ad-hoc SwiftUI view (no registered route required). |
| `navigate(route:view:bottomBarHidingBehavior:animated:)` | Push a view with a custom internal route key. |
| `popBackStack()` | Pop the current screen. |
| `popBackStack(to:including:animated:)` | Pop to a specific route in the stack. |
| `replaceStack(with:startingFrom:excludeStart:animated:)` | Replace part of the navigation stack (useful for multi-step flows). |
| `replaceLast(with:route:animated:)` | Replace only the top-most screen. |

---

## Routes (NavRoute)

A **Route** is a lightweight data carrier that describes a navigation destination and its parameters. Routes conform to `NavRoute`.

```swift
struct HelpRoute: NavRoute {
    let type: HelpType?
    let navController: NavController
}

struct CreateEditRecordRoute: NavRoute {
    let router: RecordRouting
    let dependencies: CreateEditRecord.Dependencies
    let editRecord: Record?
    let newRecordType: RecordType
    let resultNavBehavior: CreateEditRecord.ResultNavBehavior
}
```

Routes carry everything needed to build the destination screen. The `NavDestination` system maps routes to actual Views/ViewControllers.

---

## Module-Level Navigation (NavDestination)

Modules declare their available routes via `ModuleNavRouting` and `@NavDestinationListBuilder`. This registers routes in the app-level `FeatureRouterService`.

```swift
extension RecordModule: ModuleNavRouting {
    @NavDestinationListBuilder
    public static func setupNavGraph(featureRouterService: FeatureRouterService) -> [GraphDestination] {
        ViewDestination(routeType: DetailsRoute.self) { route, _ in
            let viewModel = RecordDetailsViewModel(
                recordStore: route.dependencies.recordStore,
                measurementSystem: route.dependencies.measurementSystem,
                initialModel: route.model,
                articleId: route.articleId
            )
            RecordDetailsView(router: route.router, activityIndicator: route.dependencies.activityIndicator, viewModel: viewModel)
        }
        ViewDestination(routeType: CreateEditRecordRoute.self, bottomBarHidingBehavior: .hidesWhenPushed) { route, _ in
            CreateEditRecordView(
                viewModel: CreateEditRecordViewModel(...),
                router: route.router,
                indicatorProvider: route.dependencies.activityIndicator,
                resultNavBehavior: route.resultNavBehavior
            )
        }
    }
}
```

**Pattern:** The route carries dependencies → the `NavDestination` closure builds the ViewModel and View → the Router is passed along for further navigation.

### FeatureRoute

For cross-module routes (where the destination module handles its own view creation), use `FeatureRoute`:

```swift
public struct SettingsRoute: FeatureRoute, NavRoute {
    let navController: NavController

    init(navController: NavController) {
        self.navController = navController
    }
}
```

`FeatureRoute` routes are resolved by the `FeatureRouterService`, which delegates to the destination module's nav graph.

---

## Data Passing

### Forward (to next screen)

The Router passes data as parameters when creating the next screen's ViewModel or Route:

```swift
func navigateToDetails(model: RecordDetailsUIModel, articleId: Int?) {
    navController.navigateTo(
        DetailsRoute(router: self, dependencies: ..., model: model, articleId: articleId)
    )
}
```

### Backward (to previous screen)

Use one of these patterns:

| Pattern | When to use |
|---------|-------------|
| **`CurrentValueSubject<Data, Never>`** | Shared reactive state between two screens that both need to observe changes. Preferred for edit flows. |
| **Delegate / Callback** | One-shot result communication (e.g. created item returned to list). |
| **Scoped Store** | Complex shared state across multiple screens in a flow. The store is created by the Router and injected into all ViewModels. Deallocated when the flow is dismissed. |

#### CurrentValueSubject example

```swift
// Router creates shared subject:
let selectedItemSubject = CurrentValueSubject<Item?, Never>(nil)

// Injects into both ViewModels:
let listVM = ItemListViewModel(selectedItem: selectedItemSubject)
let detailVM = ItemDetailViewModel(selectedItem: selectedItemSubject)

// Either screen can update:
selectedItemSubject.send(newItem)
// The other reacts via Combine subscription.
```

#### Callback example

```swift
func navigateToCreateRecord(onCreated: @escaping (Record) -> Void) {
    let route = CreateRecordRoute(
        dependencies: ...,
        onCreated: onCreated
    )
    navController.navigateTo(route)
}
```

#### Scoped Store example

```swift
// Router creates a scoped store (NOT registered in DI):
let sharedData = CreateEditRecord.SharedRecordData(record: editRecord, newRecordType: recordType, measurementSystem: system)

// Injected into multiple ViewModels in the flow:
let createVM = CreateEditRecordViewModel(editingRecord: sharedData, ...)
let thresholdVM = RecordThresholdViewModel(recordData: sharedData, ...)
```

See [Domain Layer — Sharing Data Between Screens](domain-layer.md#sharing-data-between-screens) for detailed patterns.

---

## Internal Routing (Multi-Screen Flows)

For features with several screens in a sub-flow, define an **internal route enum** and extend `NavController` for convenience:

```swift
enum AccountsInternalRoute {
    case manageMember
    case settings
    case invites
    case help

    var key: String { "\(Self.self).\(self)" }
}

extension NavController {
    func navigateTo<V: View>(route: AccountsInternalRoute, destination: V, animated: Bool = true) {
        navigate(route: AdHocRoute(key: route.key), view: destination, animated: animated)
    }

    func popBack(to route: AccountsInternalRoute, including: Bool, animated: Bool = true) {
        popBackStack(to: route.key, including: including, animated: animated)
    }
}
```

This keeps route keys consistent within a feature without requiring module-level NavDestination registration.

---

## Router Scoping

| Scope | When to use |
|-------|-------------|
| **One router per screen** | Each screen has a unique set of destinations. Most common. |
| **One router per feature** | A feature has a limited number of tightly coupled screens that share context (e.g. a multi-step creation wizard). The Router acts as a lightweight flow coordinator. |
| **Nested routers** | A parent Router creates child Routers for sub-flows. Each child owns its sub-navigation. |

### Nested Router example

```swift
func openManageMembers(animated: Bool) {
    let childRouter = MemberAccountsRouter(dependencies: dependencies, navController: navController)
    let viewModel = MemberAccountsView.ViewModel(repository: repository, ...)
    let view = MemberAccountsView(viewModel: viewModel, router: childRouter, ...)
    navController.navigateTo(route: .manageMember, destination: view, animated: animated)
}
```

---

## Previews and Testing

### SwiftUI Previews

Provide a lightweight `PreviewRouter` (or mock) for previews:

```swift
#Preview {
    RecordDetailsView(
        router: PreviewRecordRouter(),
        activityIndicator: PreviewActivityIndicator(),
        viewModel: PreviewObservableStateViewModel(initialState: .preview)
    )
}
```

### Unit Testing

Since Routers are protocol-based, stub them in ViewModel/View tests:

```swift
final class StubRecordRouter: RecordRouting {
    var navigateToDetailsCalled = false
    var lastDetailModel: RecordDetailsUIModel?

    func navigateToDetails(model: RecordDetailsUIModel, articleId: Int?) {
        navigateToDetailsCalled = true
        lastDetailModel = model
    }
    // ...
}
```

---

## Summary of Rules

1. **Views and ViewModels must not know about navigation.** All navigation goes through the Router.
2. **Each screen defines a `*Routing` protocol.** This is the contract for its navigation capabilities.
3. **Routers create ViewModels and inject dependencies.** The View never creates its own ViewModel.
4. **Use `NavController`** for all navigation operations (never use `UINavigationController` directly).
5. **Routes are data carriers.** They hold parameters and dependencies needed to build the destination.
6. **Modules register their NavDestinations** via `@NavDestinationListBuilder` in `setupNavGraph`.
7. **Data passing backward** uses `CurrentValueSubject`, callbacks, or scoped Stores — never direct ViewModel access.
8. **One Router per screen** is the default; share a Router across a multi-step flow only when screens are tightly coupled.

---

## Reference

- [ViewState MVVM](viewstate-mvvm.md)
- [Domain Layer — Sharing Data Between Screens](domain-layer.md#sharing-data-between-screens)
- [App Architecture](app-architecture.md)
