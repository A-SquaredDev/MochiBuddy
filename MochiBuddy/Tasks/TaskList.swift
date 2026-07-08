//
//  TaskList.swift
//  MochiBuddy
//
//  Domain model for users/{uid}/lists — the user's task categories.
//  Tasks with no list live in the implicit Inbox.
//

import Foundation

struct TaskList: Equatable, Identifiable {
    let id: String
    var name: String
    /// CSS-style hex ("#C9A6FF") — matches the design token wire format.
    var colorHex: String
    var icon: String
    var order: Int
}

enum TaskListDefaults {
    /// Swatch choices from the design's "New list" row.
    static let colorChoices = ["#C9A6FF", "#FF9DC4", "#8FD3F4", "#9BE6B4"]
    static let icon = "🏷️"
}
