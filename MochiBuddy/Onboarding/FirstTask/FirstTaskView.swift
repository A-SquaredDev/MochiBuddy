//
//  FirstTaskView.swift
//  MochiBuddy
//

import SwiftUI

struct FirstTaskView: View {
    @State var viewModel: ObservableStateViewModel<
        FirstTaskBehavior.UIState,
        FirstTaskBehavior.ViewAction,
        FirstTaskBehavior.NavigationEvent
    >
    let router: any OnboardingRouting

    @Environment(\.mochiTheme) private var theme
    @FocusState private var inputFocused: Bool

    var body: some View {
        OnbScaffold(
            progress: (index: 1, total: 8),
            onBack: { router.navigateBack() },
            centered: false
        ) {
            VStack(alignment: .leading, spacing: 16) {
                OnbHeading(
                    eyebrow: "Your first task",
                    title: "What's one thing on your mind?",
                    bodyText: "Jot it down — Mochi's already rooting for you to check it off.",
                    align: .leading
                )
                .padding(.top, 8)

                taskInput

                FlowChips(items: viewModel.suggestions) { suggestion in
                    viewModel.trigger(.suggestionTapped(suggestion))
                }

                VStack(spacing: 4) {
                    MochiPetView(vitality: 90, size: 110)
                    Text("Ooh, a fresh start ✨")
                        .font(MochiFont.display(13.5, weight: .semibold))
                        .foregroundStyle(theme.ink)
                    Text("Finish it later and I'll do a happy wiggle.")
                        .font(MochiFont.body(11.5, weight: .bold))
                        .foregroundStyle(theme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            }
        } footer: {
            MochiButton(
                title: "Add & continue",
                isLoading: viewModel.isSaving,
                isDisabled: !viewModel.canAdd
            ) {
                viewModel.trigger(.addTapped)
            }
            MochiTextLink(title: "Skip for now") {
                viewModel.trigger(.skipTapped)
            }
        }
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .next:
                router.navigateToFlavorPicker()
            }
        }
    }

    private var taskInput: some View {
        HStack(spacing: 7) {
            Text("✏️").font(.system(size: 13))
            TextField(
                "What's next on the list?",
                text: viewModel.collectBinding(for: \.title, action: { .titleChanged($0) })
            )
            .font(MochiFont.body(13, weight: .bold))
            .foregroundStyle(theme.ink)
            .focused($inputFocused)
            .submitLabel(.done)
            .onSubmit { if viewModel.canAdd { viewModel.trigger(.addTapped) } }

            Button {
                viewModel.trigger(.addTapped)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.primaryInk)
                    .frame(width: 24, height: 24)
                    .background(theme.primary, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canAdd)
            .opacity(viewModel.canAdd ? 1 : 0.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: MochiRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: MochiRadius.md)
                .stroke(inputFocused ? theme.primary : theme.line, lineWidth: 2)
        )
        .animation(MochiMotion.soft, value: inputFocused)
    }
}

/// Suggestion pills that wrap onto multiple lines.
private struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        HStack(spacing: 7) {
            ForEach(items, id: \.self) { item in
                Button {
                    Haptics.impact(.light)
                    onTap(item)
                } label: {
                    Text(item)
                        .font(MochiFont.display(12, weight: .medium))
                        .foregroundStyle(theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(theme.surface2, in: Capsule())
                        .overlay(Capsule().stroke(theme.line, lineWidth: 1.5))
                }
                .buttonStyle(SquishButtonStyle())
            }
            Spacer(minLength: 0)
        }
    }
}
