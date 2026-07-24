//
//  MochiWidgetIntents.swift
//  MochiWidget
//
//  The two home-screen interactions (design doc: Widgets → Interactions).
//  Pet stays entirely inside the App Group - buffer lift, reload, done.
//  Complete queues for the app to make durable (the widget process is
//  too small to carry Firestore) and optimistically updates the snapshot
//  so the row reflects the tap instantly.
//

import AppIntents
import Foundation
import WidgetKit

struct PetMochiIntent: AppIntent {
    static let title: LocalizedStringResource = "Pet Mochi"
    static let description = IntentDescription("A little comfort for Mochi.")

    func perform() async throws -> some IntentResult {
        UserDefaultsComfortBufferStore(defaults: MochiAppGroup.defaults).add(
            lift: TreatCatalog.Pet.lift,
            duration: TreatCatalog.Pet.duration
        )
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete task"
    static let description = IntentDescription("Check it off from the widget.")

    @Parameter(title: "Task")
    var taskId: String

    init() {}

    init(taskId: String) {
        self.taskId = taskId
    }

    func perform() async throws -> some IntentResult {
        let defaults = MochiAppGroup.defaults
        // Local context is stamped NOW, in the zone the tap happened in -
        // the app-side drain may run days later or a continent away
        // (Personal Layer, Feature 4: behavior never rewrites).
        WidgetStateStore.enqueueCompletion(
            taskId: taskId, context: .capture(), defaults: defaults
        )
        // Optimistic: drop the row now; the app-side drain persists it
        // (coins included) on next open and re-mirrors the truth.
        if var state = WidgetStateStore.load(defaults: defaults) {
            state.nextTasks.removeAll { $0.id == taskId }
            state.lastComputed = .now
            WidgetStateStore.save(state, defaults: defaults)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
