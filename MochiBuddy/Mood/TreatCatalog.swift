//
//  TreatCatalog.swift
//  MochiBuddy
//
//  Treats are priced by DURATION, not lift — the buffer caps at +30, so
//  how long the comfort lasts is what coins really buy. Every treat
//  strictly beats the free pet (~15 min). Buy = give: no inventory.
//

import Foundation

struct Treat: Equatable, Identifiable {
    let id: String
    let name: String
    let emoji: String
    let lift: Double
    let duration: TimeInterval
    let durationText: String
    let cost: Int
}

enum TreatCatalog {
    static let all: [Treat] = [
        Treat(id: "berry", name: "Sweet berry", emoji: "🍓", lift: 15, duration: 1 * 3600, durationText: "~1 hr", cost: 15),
        Treat(id: "latte", name: "Matcha latte", emoji: "🍵", lift: 16, duration: 2 * 3600, durationText: "~2 hr", cost: 22),
        Treat(id: "dango", name: "Dango", emoji: "🍡", lift: 18, duration: 3 * 3600, durationText: "~3 hr", cost: 30),
        Treat(id: "cupcake", name: "Cupcake", emoji: "🧁", lift: 20, duration: 6 * 3600, durationText: "~6 hr", cost: 55),
    ]

    /// The free action every treat must beat.
    enum Pet {
        static let name = "Pet Mochi"
        static let emoji = "🫧"
        static let lift: Double = 8
        static let duration: TimeInterval = 15 * 60
        static let durationText = "~15 min"
    }
}
