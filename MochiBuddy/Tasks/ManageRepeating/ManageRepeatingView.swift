//
//  ManageRepeatingView.swift
//  MochiBuddy
//

import SwiftUI

struct ManageRepeatingView: View {
    @State var viewModel: StateViewModel<
        ManageRepeatingBehavior.UIState,
        ManageRepeatingBehavior.ViewAction
    >
    let router: any BackRouting
    /// Builds the task-editor sheet for a repeating series (routers own DI).
    let taskEditor: (TaskItem) -> AnyView

    @Environment(\.mochiTheme) private var theme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ScreenTopBar(
                    title: "Repeating tasks",
                    subtitle: "Tap a series to adjust it",
                    onBack: { router.navigateBack() }
                )

                if viewModel.series.isEmpty {
                    emptyHint
                } else {
                    VStack(spacing: 8) {
                        ForEach(viewModel.series) { series in
                            seriesRow(series)
                        }
                    }
                }
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 24, trailing: 18))
        }
        .background(theme.bg.ignoresSafeArea())
        .onLoad { viewModel.trigger(.load) }
        .sheet(
            item: viewModel.collectBinding(for: \.editingSeries, action: { _ in .seriesEditorDismissed })
        ) { editing in
            taskEditor(editing.task)
        }
    }

    /// A live recurring series - tap to edit its rule in the task editor.
    private func seriesRow(_ series: ManageRepeatingBehavior.RepeatingUIItem) -> some View {
        Button {
            Haptics.impact(.light)
            viewModel.trigger(.seriesTapped(id: series.id))
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                VStack(alignment: .leading, spacing: 1) {
                    Text(series.title)
                        .font(MochiFont.body(13, weight: .heavy))
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                    Text(series.cadence)
                        .font(MochiFont.body(11, weight: .bold))
                        .foregroundStyle(theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                MochiRowChevron()
            }
            .padding(EdgeInsets(top: 11, leading: 12, bottom: 11, trailing: 12))
            .background(theme.surface2, in: RoundedRectangle(cornerRadius: MochiRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: MochiRadius.md)
                    .stroke(theme.line, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyHint: some View {
        MochiCard {
            HStack(spacing: 11) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.muted)
                Text("No repeating tasks yet. Set a repeat on any task and \(viewModel.petName) will keep it coming back here.")
                    .font(MochiFont.body(12, weight: .bold))
                    .foregroundStyle(theme.muted)
            }
        }
    }
}
