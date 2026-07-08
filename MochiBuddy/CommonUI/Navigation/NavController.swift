//
//  NavController.swift
//  MochiBuddy
//
//  CommonUI — the navigation abstraction Routers talk to.
//  Backed by SwiftUI NavigationStack via NavHost; Views and ViewModels
//  never touch it directly.
//

import SwiftUI

/// A lightweight data carrier describing a navigation destination.
protocol NavRoute {
    var key: String { get }
}

extension NavRoute {
    var key: String { String(describing: Self.self) }
}

/// Route for ad-hoc pushes that don't need a registered destination type.
struct AdHocRoute: NavRoute {
    let key: String
}

@MainActor
@Observable
final class NavController {

    struct Entry: Identifiable, Hashable {
        let id = UUID()
        let key: String
        let content: AnyView

        static func == (lhs: Entry, rhs: Entry) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    var stack: [Entry] = []

    /// Push an ad-hoc SwiftUI view.
    func navigate(view: AnyView, animated: Bool = true) {
        navigate(route: AdHocRoute(key: "adhoc"), view: view, animated: animated)
    }

    /// Push a view with a route key (enables popBackStack(to:)).
    func navigate(route: NavRoute, view: AnyView, animated: Bool = true) {
        mutate(animated: animated) { $0.append(Entry(key: route.key, content: view)) }
    }

    /// Pop the current screen.
    func popBackStack() {
        mutate(animated: true) { _ = $0.popLast() }
    }

    /// Pop to a specific route in the stack.
    func popBackStack(to key: String, including: Bool = false, animated: Bool = true) {
        guard let index = stack.lastIndex(where: { $0.key == key }) else { return }
        let end = including ? index : index + 1
        mutate(animated: animated) { $0 = Array($0.prefix(end)) }
    }

    /// Replace the whole pushed stack with a single destination
    /// (multi-step flows landing on a new root-of-flow screen).
    func replaceStack(with view: AnyView, route: NavRoute = AdHocRoute(key: "adhoc"), animated: Bool = true) {
        mutate(animated: animated) { $0 = [Entry(key: route.key, content: view)] }
    }

    /// Replace only the top-most screen.
    func replaceLast(with view: AnyView, route: NavRoute = AdHocRoute(key: "adhoc"), animated: Bool = true) {
        mutate(animated: animated) {
            _ = $0.popLast()
            $0.append(Entry(key: route.key, content: view))
        }
    }

    /// Pop everything back to the NavHost root.
    func popToRoot(animated: Bool = true) {
        mutate(animated: animated) { $0.removeAll() }
    }

    private func mutate(animated: Bool, _ change: (inout [Entry]) -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = !animated
        withTransaction(transaction) { change(&stack) }
    }
}

/// Hosts a NavController-driven stack. The root view is fixed; Routers
/// push/pop destinations through the controller.
struct NavHost: View {
    @Bindable private var controller: NavController
    private let root: AnyView

    init(controller: NavController, root: AnyView) {
        self.controller = controller
        self.root = root
    }

    var body: some View {
        NavigationStack(path: $controller.stack) {
            root
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: NavController.Entry.self) { entry in
                    entry.content
                        .toolbar(.hidden, for: .navigationBar)
                }
        }
    }
}
