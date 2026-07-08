//
//  MochiTheme.swift
//  MochiBuddy
//
//  Design tokens ported from the Mochi design system (tokens/themes.css,
//  colors.css, radii.css). Each flavor is a full token set; Black Sesame is
//  the dark flavor and overrides the status tokens.
//

import SwiftUI

struct MochiTheme: Equatable, Identifiable {
    let id: String
    let name: String
    let isDark: Bool

    let bg: Color
    let surface: Color
    let surface2: Color
    let ink: Color
    let muted: Color
    let line: Color
    let primary: Color
    let primaryInk: Color   // text/icon ON primary fill
    let primaryText: Color  // primary color for text on soft/light bg
    let primarySoft: Color  // tinted fill: ghost buttons, chips, tracks
    let accent2: Color      // lighter accent — gradient partner
    let pet: Color
    let pet2: Color
    let petCheek: Color
    let danger: Color
    let dangerSoft: Color
    let warn: Color
    let warnSoft: Color

    static let strawberry = MochiTheme(
        id: "strawberry", name: "Strawberry", isDark: false,
        bg: Color(hex: 0xFFF3F5), surface: Color(hex: 0xFFFFFF), surface2: Color(hex: 0xFFF7F9),
        ink: Color(hex: 0x4A2B33), muted: Color(hex: 0x886570), line: Color(hex: 0xF3DCE2),
        primary: Color(hex: 0xD6335F), primaryInk: Color(hex: 0xFFFFFF), primaryText: Color(hex: 0xC42655),
        primarySoft: Color(hex: 0xFFE0E8), accent2: Color(hex: 0xFFB3C1),
        pet: Color(hex: 0xFFB6C8), pet2: Color(hex: 0xFF9FB6), petCheek: Color(hex: 0xFF7CA0),
        danger: Color(hex: 0xB0301F), dangerSoft: Color(hex: 0xFADEDA),
        warn: Color(hex: 0x8A5300), warnSoft: Color(hex: 0xFFEAC8)
    )

    static let matcha = MochiTheme(
        id: "matcha", name: "Matcha", isDark: false,
        bg: Color(hex: 0xF1F7EA), surface: Color(hex: 0xFFFFFF), surface2: Color(hex: 0xF7FBF1),
        ink: Color(hex: 0x2E3A24), muted: Color(hex: 0x67734E), line: Color(hex: 0xDDE9CD),
        primary: Color(hex: 0x3B7827), primaryInk: Color(hex: 0xFFFFFF), primaryText: Color(hex: 0x3B7827),
        primarySoft: Color(hex: 0xE5F2D7), accent2: Color(hex: 0x7FB85E),
        pet: Color(hex: 0xC6E8AE), pet2: Color(hex: 0xAEDB90), petCheek: Color(hex: 0x8FCB6A),
        danger: Color(hex: 0xB0301F), dangerSoft: Color(hex: 0xFADEDA),
        warn: Color(hex: 0x8A5300), warnSoft: Color(hex: 0xFFEAC8)
    )

    static let ube = MochiTheme(
        id: "ube", name: "Ube", isDark: false,
        bg: Color(hex: 0xF5F1FC), surface: Color(hex: 0xFFFFFF), surface2: Color(hex: 0xFAF7FE),
        ink: Color(hex: 0x382A4D), muted: Color(hex: 0x786A93), line: Color(hex: 0xE7DEF6),
        primary: Color(hex: 0x7B4BC4), primaryInk: Color(hex: 0xFFFFFF), primaryText: Color(hex: 0x7340BE),
        primarySoft: Color(hex: 0xE7DBFA), accent2: Color(hex: 0xC6A8F0),
        pet: Color(hex: 0xCFB6F2), pet2: Color(hex: 0xBF9DEC), petCheek: Color(hex: 0xA97FE0),
        danger: Color(hex: 0xB0301F), dangerSoft: Color(hex: 0xFADEDA),
        warn: Color(hex: 0x8A5300), warnSoft: Color(hex: 0xFFEAC8)
    )

    static let mango = MochiTheme(
        id: "mango", name: "Mango", isDark: false,
        bg: Color(hex: 0xFFF7EA), surface: Color(hex: 0xFFFFFF), surface2: Color(hex: 0xFFFBF2),
        ink: Color(hex: 0x4D3A1F), muted: Color(hex: 0x8A6C45), line: Color(hex: 0xF4E6CC),
        primary: Color(hex: 0xF2820C), primaryInk: Color(hex: 0x3D2400), primaryText: Color(hex: 0x9A5400),
        primarySoft: Color(hex: 0xFFE6C0), accent2: Color(hex: 0xFFCB77),
        pet: Color(hex: 0xFFD98A), pet2: Color(hex: 0xFFC65C), petCheek: Color(hex: 0xFFA93C),
        danger: Color(hex: 0xB0301F), dangerSoft: Color(hex: 0xFADEDA),
        warn: Color(hex: 0x8A5300), warnSoft: Color(hex: 0xFFEAC8)
    )

    static let sesame = MochiTheme(
        id: "sesame", name: "Black Sesame", isDark: true,
        bg: Color(hex: 0x211E2A), surface: Color(hex: 0x2E2A38), surface2: Color(hex: 0x353040),
        ink: Color(hex: 0xF3EEF7), muted: Color(hex: 0xA79FB5), line: Color(hex: 0x413A50),
        primary: Color(hex: 0xC9A6FF), primaryInk: Color(hex: 0x241A33), primaryText: Color(hex: 0xC9A6FF),
        primarySoft: Color(hex: 0x453A58), accent2: Color(hex: 0xFF9DC4),
        pet: Color(hex: 0x7E7492), pet2: Color(hex: 0x6A6082), petCheek: Color(hex: 0xB79DE0),
        danger: Color(hex: 0xFF9DA6), dangerSoft: Color(hex: 0x4E2B31),
        warn: Color(hex: 0xFFC777), warnSoft: Color(hex: 0x4A3A1E)
    )

    static let all: [MochiTheme] = [.sesame, .strawberry, .matcha, .ube, .mango]

    static func theme(id: String) -> MochiTheme {
        all.first { $0.id == id } ?? .sesame
    }
}

/// Radii tokens — everything is soft; primary interactive elements are pills.
enum MochiRadius {
    static let lg: CGFloat = 26   // flavor cards, big panels
    static let xl: CGFloat = 28   // outer card shell
    static let md: CGFloat = 18   // inputs, todos, reminders
    static let sm: CGFloat = 13   // small tiles
}

/// Motion tokens — `bounce` is the springy Mochi overshoot.
enum MochiMotion {
    static let bounce = Animation.spring(response: 0.38, dampingFraction: 0.6)
    static let soft = Animation.easeInOut(duration: 0.25)
    static let mood = Animation.easeInOut(duration: 0.4)
}

extension EnvironmentValues {
    @Entry var mochiTheme: MochiTheme = .sesame
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
