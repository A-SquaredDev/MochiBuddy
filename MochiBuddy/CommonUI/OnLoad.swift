//
//  OnLoad.swift
//  MochiBuddy
//
//  CommonUI — fires exactly once per view lifetime, unlike onAppear.
//

import SwiftUI

private struct OnLoadModifier: ViewModifier {
    @State private var hasLoaded = false
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            action()
        }
    }
}

extension View {
    /// Triggers `action` once, the first time the view appears.
    func onLoad(perform action: @escaping () -> Void) -> some View {
        modifier(OnLoadModifier(action: action))
    }
}
