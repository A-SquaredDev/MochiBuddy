//
//  TaskItem.swift
//  MochiBuddy
//
//  Domain model for users/{uid}/tasks — deliberately lean (v1).
//

import Foundation

enum TaskPriority: String {
    case low
    case med
    case high
}

/// What the user provides when capturing a task.
struct TaskDraft {
    var title: String
    var notes: String?
    var dueAt: Date?
    var hasTime = false
    var priority: TaskPriority = .med
}
