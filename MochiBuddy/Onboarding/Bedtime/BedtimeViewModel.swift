//
//  BedtimeViewModel.swift
//  MochiBuddy
//
//  5 · Quiet hours — Mochi sleeps while you do. Sensible default
//  (10:00 PM – 7:00 AM), changeable later in Settings.
//

import Foundation

final class BedtimeViewModel: ObservableStateViewModel<
    BedtimeBehavior.UIState,
    BedtimeBehavior.ViewAction,
    BedtimeBehavior.NavigationEvent
> {

    private let onboardingStore: OnboardingStore

    // Domain source of truth — wall-clock minutes, not instants.
    private var window: BedtimeWindow = .standard

    init(onboardingStore: OnboardingStore) {
        self.onboardingStore = onboardingStore
        super.init(initialState: BedtimeBehavior.UIState())
    }

    override func triggerAsync(_ action: BedtimeBehavior.ViewAction) async {
        switch action {
        case .load:
            rebuildState(editing: .none)

        case .bedtimeTapped:
            rebuildState(editing: uiState.editing == .bedtime ? .none : .bedtime)

        case .wakeTapped:
            rebuildState(editing: uiState.editing == .wake ? .none : .wake)

        case .bedtimeChanged(let date):
            window.startMinutes = Self.minutes(from: date)
            rebuildState(editing: uiState.editing)

        case .wakeChanged(let date):
            window.endMinutes = Self.minutes(from: date)
            rebuildState(editing: uiState.editing)

        case .continueTapped:
            state.isSaving = true
            await onboardingStore.saveBedtime(window)
            state.isSaving = false
            setNavigationEvent(.next)
        }
    }

    private func rebuildState(editing: BedtimeBehavior.EditTarget) {
        setUIState(
            uiState
                .updating(\.bedtimeText, to: Self.format(minutes: window.startMinutes))
                .updating(\.wakeText, to: Self.format(minutes: window.endMinutes))
                .updating(\.bedtimeDate, to: Self.date(from: window.startMinutes))
                .updating(\.wakeDate, to: Self.date(from: window.endMinutes))
                .updating(\.editing, to: editing)
        )
    }

    private static func minutes(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private static func date(from minutes: Int) -> Date {
        Calendar.current.date(
            bySettingHour: minutes / 60,
            minute: minutes % 60,
            second: 0,
            of: .now
        ) ?? .now
    }

    private static func format(minutes: Int) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date(from: minutes))
    }
}
