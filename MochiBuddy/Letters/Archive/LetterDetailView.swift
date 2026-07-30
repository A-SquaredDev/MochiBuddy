//
//  LetterDetailView.swift
//  MochiBuddy
//
//  One letter, read in full. Works pushed (archive, with back) or as a
//  sheet (Home envelope / notification tap, with close). Sharing renders
//  the Feature 1-deferred card via ImageRenderer: PRIVATE variant by
//  default; full is a per-share opt-in and rough letters never offer it.
//

import SwiftUI

struct LetterDetailView: View {

    /// A rendered card en route to the share sheet.
    private struct ShareItem: Identifiable {
        let variant: String
        let image: UIImage
        var id: String { variant }
    }

    @State var viewModel: LetterDetailViewModel
    /// Nil when pushed (back arrow via router); set when presented as a
    /// sheet (close button).
    var onClose: (() -> Void)?
    var onBack: (() -> Void)?

    @State private var shareItem: ShareItem?
    @Environment(\.mochiTheme) private var theme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ScreenTopBar(
                    title: viewModel.weekTitle,
                    subtitle: viewModel.dateRangeText,
                    onBack: onBack ?? onClose ?? {}
                ) {
                    shareMenu
                }

                if let saveResult = viewModel.saveResultText {
                    saveToast(saveResult)
                }

                letterCard
            }
            .padding(EdgeInsets(top: 8, leading: 18, bottom: 24, trailing: 18))
        }
        .background(theme.bg)
        .onLoad { viewModel.trigger(.load) }
        .sheet(item: $shareItem) { item in
            // UIActivityViewController, not ShareLink: a ShareLink inside
            // a Menu never presented (its activation lost to the menu
            // dismissal), and the UIKit sheet also gives Save Image plus a
            // completion hook so letter_shared logs only on a REAL share.
            ActivityShareSheet(image: item.image) { completed in
                if completed {
                    viewModel.trigger(.sharedTapped(variant: item.variant))
                }
                shareItem = nil
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var letterCard: some View {
        MochiCard(padding: EdgeInsets(top: 20, leading: 18, bottom: 20, trailing: 18)) {
            VStack(alignment: .leading, spacing: 14) {
                MochiPetView(
                    mood: .content, size: 64, squishOnTap: false,
                    petName: viewModel.petName
                )
                .frame(maxWidth: .infinity)
                Text(viewModel.bodyText)
                    .font(MochiFont.body(14, weight: .bold))
                    .foregroundStyle(theme.ink)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !viewModel.adoptionLine.isEmpty {
                    Text(viewModel.adoptionLine)
                        .font(MochiFont.body(10.5, weight: .heavy))
                        .foregroundStyle(theme.muted)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Letter from \(viewModel.petName). \(viewModel.bodyText)")
    }

    // MARK: - Sharing

    private var shareMenu: some View {
        Menu {
            Button {
                if let image = renderCardImage(text: viewModel.letter.privateRenderedText) {
                    shareItem = ShareItem(variant: "private", image: image)
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            if viewModel.offersFullShare {
                Button {
                    if let image = renderCardImage(text: viewModel.letter.fullRenderedText) {
                        shareItem = ShareItem(variant: "full", image: image)
                    }
                } label: {
                    Label("Share with task names", systemImage: "square.and.arrow.up.on.square")
                }
            }
            // First-class save: the share sheet's own Save Image action is
            // environment-dependent; this one always exists. Same privacy
            // default as Share - always the private variant.
            Button {
                if let image = renderCardImage(text: viewModel.letter.privateRenderedText) {
                    viewModel.trigger(.saveToPhotos(image))
                }
            } label: {
                Label("Save to Photos", systemImage: "square.and.arrow.down")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(theme.primaryText)
        }
        .accessibilityLabel("Share this letter")
    }

    private func saveToast(_ text: String) -> some View {
        Text(text)
            .font(MochiFont.body(11.5, weight: .heavy))
            .foregroundStyle(theme.ink)
            .padding(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
            .background(theme.surface2, in: Capsule())
            .frame(maxWidth: .infinity)
            .transition(.opacity)
            .task {
                try? await Task.sleep(for: .seconds(2.5))
                viewModel.trigger(.dismissSaveResult)
            }
    }

    /// Renders the card at share scale. Private text by default; the full
    /// variant only arrives via the explicit opt-in.
    private func renderCardImage(text: String) -> UIImage? {
        let card = LetterShareCard(
            letterText: text,
            petName: viewModel.petName,
            adoptionLine: viewModel.adoptionLine,
            weekTitle: viewModel.weekTitle,
            theme: theme
        )
        // ImageRenderer content gets no app environment - hand the theme
        // through explicitly or the pet and placeholder render default.
        let renderer = ImageRenderer(content: card.environment(\.mochiTheme, theme))
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// The UIKit share sheet: image payload (Save Image, Messages, Mail, the
/// works) plus the completion hook SwiftUI's ShareLink doesn't offer.
private struct ActivityShareSheet: UIViewControllerRepresentable {
    let image: UIImage
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onFinish(completed)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// The shareable postcard (Personal Layer, Feature 3): letter text, the
/// pet pose, the adoption-age line, a small wordmark.
struct LetterShareCard: View {
    let letterText: String
    let petName: String
    let adoptionLine: String
    let weekTitle: String
    let theme: MochiTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(weekTitle)
                    .font(MochiFont.display(15))
                    .foregroundStyle(theme.muted)
                Spacer()
                MochiPetView(mood: .content, size: 52, squishOnTap: false, showsSparkles: false)
            }
            Text(letterText)
                .font(MochiFont.body(15, weight: .bold))
                .foregroundStyle(theme.ink)
                .lineSpacing(5)
            HStack(spacing: 6) {
                if !adoptionLine.isEmpty {
                    Text(adoptionLine)
                        .font(MochiFont.body(11, weight: .heavy))
                        .foregroundStyle(theme.muted)
                }
                Spacer()
                HStack(spacing: 4) {
                    MochiMark(size: 13, color: theme.muted)
                    Text("MochiBuddy")
                        .font(MochiFont.display(11, weight: .semibold))
                        .foregroundStyle(theme.muted)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(theme.bg)
    }
}
