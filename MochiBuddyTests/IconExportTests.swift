//
//  IconExportTests.swift
//  MochiBuddyTests
//
//  Not a test: a dev tool that renders MochiPetView into PNG art for icon
//  work. Skipped on normal test runs; gated by a marker file (env vars
//  don't reliably reach app-hosted test processes). Export with:
//
//    touch .mochi-export-icons
//    xcodebuild -project MochiBuddy.xcodeproj -scheme MochiBuddy \
//      -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.1' \
//      -only-testing:MochiBuddyTests/IconExportTests test
//    rm .mochi-export-icons
//
//  Output lands in <repo>/IconExports/:
//    layers/mochi-<flavor>.png    transparent-background pet, 1024px wide,
//                                 for Icon Composer's foreground layer
//    previews/icon-<flavor>.png   1024x1024 composed mock (gradient ground
//                                 + pet) to judge the palette pairings
//  Previews include two Black Sesame grounds (lavender + dark) since its
//  in-app pet/bg pairing is too low-contrast for a home-screen icon.
//

import SwiftUI
import Testing
import UIKit
@testable import MochiBuddy

/// Repo root on the host filesystem - simulator test processes share it.
private nonisolated var repoRoot: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // MochiBuddyTests/
        .deletingLastPathComponent()   // repo root
}

private nonisolated var exportRequested: Bool {
    FileManager.default.fileExists(atPath: repoRoot.appending(path: ".mochi-export-icons").path)
}

@MainActor
struct IconExportTests {

    @Test("export Mochi icon layers and previews", .enabled(if: exportRequested))
    func exportIconArt() throws {
        let layersDir = repoRoot.appending(path: "IconExports/layers")
        let previewsDir = repoRoot.appending(path: "IconExports/previews")
        try FileManager.default.createDirectory(at: layersDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: previewsDir, withIntermediateDirectories: true)

        for theme in MochiTheme.all {
            try write(
                pet(theme: theme, size: 1024),
                to: layersDir.appending(path: "mochi-\(theme.id).png")
            )
            try write(
                preview(theme: theme, ground: [theme.accent2, theme.primary]),
                to: previewsDir.appending(path: "icon-\(theme.id).png")
            )
        }

        // Sesame's dark-ground alternative: in-app bg + a lavender rim light
        // so the muted pet doesn't sink into the ground.
        let sesame = MochiTheme.sesame
        try write(
            preview(theme: sesame, ground: [sesame.surface2, sesame.bg], rimLight: sesame.primary),
            to: previewsDir.appending(path: "icon-sesame-dark.png")
        )

        print("MOCHI_EXPORT_ICONS: wrote \(MochiTheme.all.count) layers + \(MochiTheme.all.count + 1) previews to \(repoRoot.appending(path: "IconExports").path)")
    }

    // MARK: - Compositions

    private func pet(theme: MochiTheme, size: CGFloat, rimLight: Color? = nil) -> some View {
        MochiPetView(mood: .thriving, size: size, squishOnTap: false, showsSparkles: false)
            .shadow(color: rimLight?.opacity(0.85) ?? .clear, radius: size * 0.012)
            .environment(\.mochiTheme, theme)
    }

    /// 1024-square icon mock: accent-to-primary ground, pet at ~74% width
    /// sitting slightly below center. iOS applies its own corner mask.
    private func preview(theme: MochiTheme, ground: [Color], rimLight: Color? = nil) -> some View {
        ZStack {
            LinearGradient(colors: ground, startPoint: .top, endPoint: .bottom)
            pet(theme: theme, size: 1024 * 0.74, rimLight: rimLight)
                .offset(y: 1024 * 0.03)
        }
        .frame(width: 1024, height: 1024)
    }

    private func write(_ view: some View, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.uiImage, "render failed for \(url.lastPathComponent)")
        let data = try #require(image.pngData(), "PNG encode failed for \(url.lastPathComponent)")
        try data.write(to: url)
    }
}
