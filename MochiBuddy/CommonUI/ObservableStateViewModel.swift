//
//  ObservableStateViewModel.swift
//  MochiBuddy
//
//  CommonUI — the formalized ViewState MVVM base class.
//  View renders UIState, sends ViewAction via trigger(_:); one-shot
//  NavigationEvents are published for the View to relay to its Router.
//

import SwiftUI
import Combine

/// Used as the NavigationEvent parameter for screens that never navigate.
enum NoNavigationEvent {}

typealias StateViewModel<UIState, ViewAction> = ObservableStateViewModel<UIState, ViewAction, NoNavigationEvent>

@MainActor
@dynamicMemberLookup
class ObservableStateViewModel<UIState, ViewAction, NavigationEvent> {

    /// The observable container SwiftUI watches. Subclasses may mutate
    /// `state.<property>` directly or call `setUIState(_:)`.
    @Observable
    @dynamicMemberLookup
    final class StateContainer {
        fileprivate(set) var value: UIState

        init(_ value: UIState) {
            self.value = value
        }

        subscript<Value>(dynamicMember keyPath: WritableKeyPath<UIState, Value>) -> Value {
            get { value[keyPath: keyPath] }
            set { value[keyPath: keyPath] = newValue }
        }
    }

    let state: StateContainer
    var cancellables = Set<AnyCancellable>()

    private let navigationSubject = PassthroughSubject<NavigationEvent, Never>()

    /// One-shot navigation requests. Stored (stable identity) so SwiftUI's
    /// `onReceive` keeps a single live subscription — a computed publisher
    /// forces a resubscribe on every render, and events sent in that window
    /// are silently dropped (PassthroughSubject doesn't buffer).
    let navigationEvents: AnyPublisher<NavigationEvent, Never>

    var uiState: UIState { state.value }

    init(initialState: UIState) {
        state = StateContainer(initialState)
        navigationEvents = navigationSubject
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    /// Dispatches an action from a synchronous context.
    func trigger(_ action: ViewAction) {
        Task { await triggerAsync(action) }
    }

    /// Override point — handle actions with async business logic.
    func triggerAsync(_ action: ViewAction) async {}

    /// The sanctioned way to replace the whole UIState from subclasses.
    func setUIState(_ newState: UIState) {
        state.value = newState
    }

    func setNavigationEvent(_ event: NavigationEvent) {
        navigationSubject.send(event)
    }

    /// Forwards key-path reads directly to UIState (`vm.title`, not `vm.uiState.title`).
    subscript<Value>(dynamicMember keyPath: KeyPath<UIState, Value>) -> Value {
        uiState[keyPath: keyPath]
    }

    /// Two-way Binding mediated by the ViewModel — writes go through trigger(_:).
    func collectBinding<Value>(for keyPath: KeyPath<UIState, Value>, action: @escaping (Value) -> ViewAction) -> Binding<Value> {
        Binding(
            get: { self.uiState[keyPath: keyPath] },
            set: { self.trigger(action($0)) }
        )
    }

    /// Boolean convenience — the action fires when the value flips to `false`
    /// (alert/sheet dismissal).
    func collectBinding(for keyPath: KeyPath<UIState, Bool>, action: ViewAction) -> Binding<Bool> {
        Binding(
            get: { self.uiState[keyPath: keyPath] },
            set: { if !$0 { self.trigger(action) } }
        )
    }
}

/// Static-state ViewModel for SwiftUI previews.
@MainActor
final class PreviewObservableStateViewModel<UIState, ViewAction, NavigationEvent>: ObservableStateViewModel<UIState, ViewAction, NavigationEvent> {
    override func triggerAsync(_ action: ViewAction) async {}
}
