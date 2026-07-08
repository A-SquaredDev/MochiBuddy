//
//  Haptics.swift
//  MochiBuddy
//
//  Squishy motion deserves squishy feedback — small helpers so every
//  control speaks the same haptic language.
//

import UIKit

@MainActor
enum Haptics {
    /// Primary actions (CTAs, check-offs).
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// Picking between options (flavors, plans, toggles).
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Milestones — finishing onboarding, restoring a membership.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
