# App Architecture

> A reference guide to the data model and layers used in the application.

---

## Introduction

The app follows **Clean Architecture** principles. The app is split into layers: API, UI, Stores, and Entities (called **DomainModels**). There are no UseCases — business logic and data orchestration live in Stores.

**Core rule:** a layer cannot have any dependencies towards an outside layer. This means:

- Never expose DTOs from API clients towards inner layers.
- Never extend or add UI-related functionality to a DomainModel (string descriptions, field visibility, date formatting, etc.).

### What is the Model Layer?

The Model Layer is not just a collection of domain entities—it encompasses:

- Domain Model entities
- Business Logic
- Validation logic
- Abstractions for getting data from various gateways
- Ability to notify ViewModels of changes

API, DB, and Cache are **external gateways**—they must be abstracted and must not leak external models into the Domain Model.

**A ViewModel should not:**

- Use DTOs
- Call API services directly
- Work with cache and caching logic
- Apply complex operations on data
- Supervise complex async scenarios

---

## Layers Overview

### 1. Domain Models

A domain model uses Swift to the fullest to expressively represent data. It has **no connection** with outside sources (API, DB, Cache).

**Data immutability:** domain models should always be defined using **immutable structs**. Each mutation should be a deliberate action done via builders or mutable variants.

Example:

```swift
// Model/WeatherInfo.swift
public struct WeatherInfo {
    public let issueDate: Date?
    public let temp: Int?
    public let apparentTemp: Int?
    public let windDirection: Int?
    public let windSpeed: Int?
    public let latitude: Double?
    public let longitude: Double?
    // ...
}
```

---

### 2. Data Layer (Repository, Networking, DTOs, Mappers)

The data layer abstracts external data sources and provides domain models to the rest of the app.

See **[Data Layer](data-layer.md)** for the full specification including:

- Repository pattern and implementation
- Networking stack (NetworkClient, Service/RequestConfiguration, DTOs)
- DTO-to-Model mapping with the `DTOMapper` protocol
- Project structure reference

---

### 3. Domain Layer (Stores)

A Store consumes one or more repositories to apply common business logic rules to data:

- Holds data available in multiple places instantly.
- Generates events when data changes.
- Produces complete domain models by aggregating multiple repositories.

**A store is always injected and never a singleton.**

See **[Domain Layer — Stores](domain-layer.md)** for the full specification including:

- Store patterns (event-driven, actor-based, single source of truth, sync state)
- When to create a Store vs. using a repository directly
- Sharing data between screens with scoped shared data objects
- Implementation examples for accounts, menu trees, content data, comments, and sync state

---

### 4. Presentation Layer (ViewState MVVM)

The presentation layer uses a formalized MVVM pattern built on `ObservableStateViewModel`. The View–ViewModel interaction is composed of:

- **UIState** (output) — an `UpdatableStruct` containing everything the view needs to render.
- **ViewAction** (input) — an enum of user intents dispatched via `trigger(_:)`.
- **NavigationEvent** — one-shot navigation requests via a Combine publisher.

#### ⚠️ MANDATORY: All ViewModels MUST inherit from `ObservableStateViewModel`

Every ViewModel in the project **must** subclass `ObservableStateViewModel<UIState, ViewAction>` from `CommonUI`. There are **no exceptions**.

- Always `import CommonUI`.
- Always subclass `ObservableStateViewModel` with your `UIState` and `ViewAction` generic parameters.
- Override `triggerAsync(_:)` for async work and `trigger(_:)` for synchronous state mutations.
- **Never** create a standalone `ObservableObject` ViewModel.
- **Never** use `@Published` to manually manage state — use the `state` property provided by the base class and mutate it via `update { }` or direct assignment.

##### ✅ Correct — inherits from ObservableStateViewModel

```swift
import CommonUI

final class FeatureViewModel: ObservableStateViewModel<FeatureViewModel.UIState, FeatureViewModel.ViewAction> {

    struct UIState: UpdatableStruct {
        var items: [Item] = []
        var isLoading = false
    }

    enum ViewAction {
        case onAppear
        case loadMore
    }

    override var initialState: UIState { UIState() }

    override func triggerAsync(_ action: ViewAction) async {
        switch action {
        case .onAppear:
            state.isLoading = true
            let items = try? await repository.fetchItems()
            state.items = items ?? []
            state.isLoading = false
        case .loadMore:
            // ...
            break
        }
    }
}
```

##### ❌ FORBIDDEN — standalone ObservableObject ViewModel

```swift
// NEVER do this. This is non-compliant and must be rewritten.
final class FeatureViewModel: ObservableObject {
    @Published var state = UIState()
    func send(_ action: ViewAction) { /* ... */ }
}
```

> **Rule for code-generation agents:** If you generate a ViewModel that does not
> inherit from `ObservableStateViewModel` (from CommonUI), the code is **non-compliant**
> and must be rewritten to subclass `ObservableStateViewModel`. There are zero exceptions.
> Always import CommonUI and always subclass ObservableStateViewModel.

See **[ViewState MVVM](viewstate-mvvm.md)** for the full specification including:

- `ObservableStateViewModel` base class API
- UIState design, `UpdatableStruct` protocol, and `collectBinding` helpers
- ViewModel implementation patterns
- View responsibilities and constraints
- Unit testing approach

See **[Routing](routing.md)** for the full Router specification including:

- `*Routing` protocol and `*Router` implementation patterns
- `NavController` API and `NavRoute` data carriers
- Module-level `NavDestination` registration
- Data passing (forward, backward, scoped stores)
- Internal routing for multi-screen flows

---

## Folder Structure

We follow **Screaming Architecture**: the folder structure should evoke the **functionality** of the system, not the implementation details. A developer looking at the top-level folders should immediately understand what the feature does—not that it uses MVVM.

### Simple Feature

For a typical feature screen, all related files (View, ViewModel, Router) live together in the same feature folder:

```
UserProfile/
├── UserProfileView.swift
├── UserProfileViewModel.swift
├── UserProfileRouter.swift
└── UserProfileViewState.swift
```

Do **not** split by layer (e.g. `Views/`, `ViewModels/`, `Routers/`). The feature folder **is** the organizing unit.

### Complex Feature with Domain Layer

For features with significant domain logic (repositories, services, mappers, models), use a domain-oriented organization within the feature folder:

```
Reports/
├── UI/
│   ├── ReportsView.swift
│   ├── ReportsViewModel.swift
│   └── ReportsRouter.swift
├── Repository/
│   └── ReportsRepository.swift
├── Network/
│   ├── ReportsService.swift
│   └── DTOs/
│       └── SingleDateStatsDTO.swift
├── Mappers/
│   └── SingleDateStatsMapper.swift
└── Model/
    └── ReportStats.swift
```

### Key Principles

- **Name folders after what the feature does**, not after patterns (avoid generic `Services/`, `Managers/`, `Helpers/`).
- **Group by feature first**, then by layer within complex features.
- **Keep related files close**—a View and its ViewModel should never be in different top-level directories.
- **Sub-features get sub-folders**—if a feature grows, split by sub-feature rather than by layer.

---

## Dos and Don'ts

### DO

- Use dependency injection.
- Write unit tests (testability is the best indicator you are on the right track).
- Apply the Boy-Scout rule: if you touch a badly written component, improve it—extract repositories and stores.

### DON'T

- Use singletons.
- Use DTOs in ViewModels.
- Misuse repos and stores: a repo has no events and must never take on store responsibilities.
- Create ViewModels that do not inherit from `ObservableStateViewModel` (from CommonUI). Every ViewModel must subclass it—no standalone `ObservableObject` ViewModels are allowed.

---

## Reference

- [Data Layer](data-layer.md)
- [Domain Layer — Stores](domain-layer.md)
- [ViewState MVVM](viewstate-mvvm.md)
