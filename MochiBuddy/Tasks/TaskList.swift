//
//  TaskList.swift
//  MochiBuddy
//
//  Domain model for users/{uid}/lists - the user's task categories.
//  Tasks with no list live in the implicit Inbox.
//

import Foundation

struct TaskList: Equatable, Identifiable {
    let id: String
    var name: String
    /// CSS-style hex ("#C9A6FF") matching the design token wire format.
    var colorHex: String
    /// SF Symbol name (lists created before the icon migration may have
    /// stored an emoji; ListRepository normalizes those on read).
    var icon: String
    var order: Int
}

enum TaskListDefaults {
    /// Swatch choices from the design's "New list" row, plus the second
    /// pastel run (peach, butter, mint, periwinkle).
    static let colorChoices = [
        "#C9A6FF", "#FF9DC4", "#8FD3F4", "#9BE6B4",
        "#FFC9A3", "#FFE8A8", "#A8E6DB", "#B7C5F9",
    ]
    static let icon = "tag.fill"
}
