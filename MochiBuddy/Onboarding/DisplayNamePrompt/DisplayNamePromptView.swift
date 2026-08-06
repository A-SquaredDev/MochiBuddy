//
//  DisplayNamePromptView.swift
//  MochiBuddy
//
//  A sheet, not a screen: this is a gap being filled, not a step being
//  taken, and the app behind it is already usable. Skip is a real exit -
//  "Mochi friend" remains a perfectly good name for someone.
//

import SwiftUI

struct DisplayNamePromptView: View {
    @State var viewModel: ObservableStateViewModel<
        DisplayNamePromptBehavior.UIState,
        DisplayNamePromptBehavior.ViewAction,
        DisplayNamePromptBehavior.NavigationEvent
    >
    let onDismiss: () -> Void

    @Environment(\.mochiTheme) private var theme
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("What should \(viewModel.mochiName) call you?")
                    .font(MochiFont.display(16, weight: .semibold))
                    .foregroundStyle(theme.ink)
                Text("Only used for greetings. You can change it any time on the You tab.")
                    .font(MochiFont.body(11.5, weight: .bold))
                    .foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 22)
            HStack(spacing: 7) {
                Image(systemName: "person")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.muted)
                TextField(
                    "Your name",
                    text: viewModel.collectBinding(for: \.draft, action: { .draftChanged($0) })
                )
                .font(MochiFont.body(14, weight: .bold))
                .foregroundStyle(theme.ink)
                .textContentType(.givenName)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isFocused)
                .onSubmit { viewModel.trigger(.saveTapped) }
                .frame(height: 22)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: MochiRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: MochiRadius.md)
                    .stroke(theme.line, lineWidth: 2)
            )
            MochiButton(title: "Save") {
                viewModel.trigger(.saveTapped)
            }
            .disabled(!viewModel.canSave || viewModel.isSaving)
            MochiTextLink(title: "Not now") {
                viewModel.trigger(.skipTapped)
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .background(theme.bg)
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .dismiss:
                // Drop the keyboard before the sheet leaves, so it does not
                // hang over Home on the way out.
                isFocused = false
                onDismiss()
            }
        }
    }
}
