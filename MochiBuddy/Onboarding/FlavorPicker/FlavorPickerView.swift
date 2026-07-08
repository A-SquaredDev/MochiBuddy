//
//  FlavorPickerView.swift
//  MochiBuddy
//

import SwiftUI

struct FlavorPickerView: View {
    @State var viewModel: ObservableStateViewModel<
        FlavorPickerBehavior.UIState,
        FlavorPickerBehavior.ViewAction,
        FlavorPickerBehavior.NavigationEvent
    >
    let router: any OnboardingRouting

    @Environment(\.mochiTheme) private var theme

    private let columns = [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)]

    var body: some View {
        OnbScaffold(
            progress: (index: 2, total: 8),
            onBack: { router.navigateBack() },
            centered: false
        ) {
            VStack(alignment: .leading, spacing: 16) {
                OnbHeading(
                    eyebrow: "Make it yours",
                    title: "Choose Mochi's flavor",
                    bodyText: "It recolours the whole app and Mochi's world. Switch anytime — they're all included.",
                    align: .leading
                )
                .padding(.top, 8)

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 9) {
                        ForEach(viewModel.flavors) { flavor in
                            FlavorSwatch(
                                flavor: flavor,
                                isSelected: flavor.id == viewModel.selectedId
                            ) {
                                viewModel.trigger(.select(flavor.id))
                            }
                        }
                    }
                    .padding(.top, 4)
                    .padding(.horizontal, 2)
                }
            }
        } footer: {
            MochiButton(title: "Continue") {
                viewModel.trigger(.continueTapped)
            }
        }
        .onLoad { viewModel.trigger(.load) }
        .onReceive(viewModel.navigationEvents) { event in
            switch event {
            case .next:
                router.navigateToBedtime()
            }
        }
    }
}

private struct FlavorSwatch: View {
    let flavor: FlavorPickerBehavior.FlavorUIItem
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        Button {
            Haptics.selection()
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(flavor.pet)
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(flavor.bg, lineWidth: 3))
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().fill(flavor.primary)
                            .frame(height: 8)
                            .frame(maxWidth: .infinity)
                            .scaleEffect(x: 0.7, anchor: .leading)
                        Capsule().fill(flavor.primary.opacity(0.4))
                            .frame(height: 8)
                            .frame(maxWidth: .infinity)
                            .scaleEffect(x: 0.45, anchor: .leading)
                    }
                }
                HStack {
                    Text(flavor.name)
                        .font(MochiFont.display(13, weight: .semibold))
                        .foregroundStyle(flavor.ink)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(flavor.primary)
                    }
                }
            }
            .padding(EdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12))
            .background(flavor.bg, in: RoundedRectangle(cornerRadius: 15))
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .padding(4)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? theme.primary : .clear, lineWidth: 2.5)
            )
            .shadow(color: isSelected ? Color.black.opacity(0.15) : .clear, radius: 10, y: 6)
        }
        .buttonStyle(SquishButtonStyle())
        .animation(MochiMotion.soft, value: isSelected)
        .accessibilityLabel("\(flavor.name) flavor")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
