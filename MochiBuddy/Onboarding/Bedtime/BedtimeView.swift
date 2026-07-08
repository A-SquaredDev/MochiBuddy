//
//  BedtimeView.swift
//  MochiBuddy
//

import SwiftUI

struct BedtimeView: View {
    @State var viewModel: ObservableStateViewModel<
        BedtimeBehavior.UIState,
        BedtimeBehavior.ViewAction,
        BedtimeBehavior.NavigationEvent
    >
    let router: any OnboardingRouting

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        OnbScaffold(
            progress: (index: 3, total: 8),
            onBack: { router.navigateBack() }
        ) {
            Halo(size: 190) {
                MochiPetView(mood: .tired, size: 140)
                    .overlay(alignment: .topTrailing) {
                        Text("🌙")
                            .font(.system(size: 26))
                            .offset(x: 8, y: -10)
                    }
            }
            OnbHeading(
                eyebrow: "Quiet hours",
                title: "When should Mochi sleep?",
                bodyText: "Mochi rests while you do — no anxious pings at 2am, and a friendly rundown of the day when you both wake up."
            )
            HStack(spacing: 10) {
                TimePill(
                    label: "Bedtime",
                    time: viewModel.bedtimeText,
                    isActive: viewModel.editing == .bedtime
                ) {
                    viewModel.trigger(.bedtimeTapped)
                }
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.muted)
                TimePill(
                    label: "Wake up",
                    time: viewModel.wakeText,
                    isActive: viewModel.editing == .wake
                ) {
                    viewModel.trigger(.wakeTapped)
                }
            }

            if viewModel.editing != .none {
                DatePicker(
                    "",
                    selection: viewModel.editing == .bedtime
                        ? viewModel.collectBinding(for: \.bedtimeDate, action: { .bedtimeChanged($0) })
                        : viewModel.collectBinding(for: \.wakeDate, action: { .wakeChanged($0) }),
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(height: 130)
                .clipped()
                .colorScheme(theme.isDark ? .dark : .light)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        } footer: {
            MochiButton(title: "Continue", isLoading: viewModel.isSaving) {
                viewModel.trigger(.continueTapped)
            }
        }
        .animation(MochiMotion.soft, value: viewModel.editing)
        .onLoad { viewModel.trigger(.load) }
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .next:
                router.navigateToNotificationPrimer()
            }
        }
    }
}

private struct TimePill: View {
    let label: String
    let time: String
    let isActive: Bool
    let onTap: () -> Void

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        Button {
            Haptics.impact(.light)
            onTap()
        } label: {
            VStack(spacing: 3) {
                Text(label.uppercased())
                    .font(MochiFont.body(10.5, weight: .heavy))
                    .kerning(0.6)
                    .foregroundStyle(theme.muted)
                Text(time)
                    .font(MochiFont.display(21, weight: .semibold))
                    .foregroundStyle(theme.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .background(theme.surface2, in: RoundedRectangle(cornerRadius: MochiRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: MochiRadius.md)
                    .stroke(isActive ? theme.primary : theme.line, lineWidth: 1.5)
            )
        }
        .buttonStyle(SquishButtonStyle())
    }
}
