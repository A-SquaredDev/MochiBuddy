//
//  MochiWidget.swift
//  MochiWidget
//
//  The glanceable Mochi (design doc: Widgets). Everything rendered here
//  comes from the App Group snapshot the app mirrors on every re-lay -
//  no Firestore, no EventKit, no network, no engine. The timeline IS the
//  notification forecast: entries pre-evaluate the same stored baseline
//  curve plus the live comfort buffer, so the widget moves through moods
//  on its own while the app is closed and can never contradict mood(now).
//

import SwiftUI
import WidgetKit

@main
struct MochiWidgetBundle: WidgetBundle {
    var body: some Widget {
        MochiWidget()
    }
}

struct MochiWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MochiWidget", provider: MochiTimelineProvider()) { entry in
            MochiWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    MochiTheme.theme(id: entry.state?.themeId ?? MochiTheme.sesame.id).bg
                }
        }
        .configurationDisplayName("Mochi")
        .description("Mochi's mood and your next task, at a glance.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

// MARK: - Timeline

struct MochiEntry: TimelineEntry {
    let date: Date
    let state: MochiWidgetState?
    /// baseline(date) + live buffer, the value the face shows.
    let displayed: Double
}

struct MochiTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> MochiEntry {
        MochiEntry(date: .now, state: nil, displayed: 58)
    }

    func getSnapshot(in context: Context, completion: @escaping (MochiEntry) -> Void) {
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MochiEntry>) -> Void) {
        // Future-dated entries straight off the stored curve: the widget
        // ages honestly with zero wasted reloads. Half-hour steps over the
        // next 12h; interactions and app foregrounds reload immediately.
        let now = Date.now
        var entries: [MochiEntry] = []
        for step in 0..<24 {
            entries.append(entry(at: now.addingTimeInterval(Double(step) * 30 * 60)))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date) -> MochiEntry {
        guard let state = WidgetStateStore.load() else {
            return MochiEntry(date: date, state: nil, displayed: 58)
        }
        let boosts = UserDefaultsComfortBufferStore(defaults: MochiAppGroup.defaults)
            .activeBoosts(now: date)
        return MochiEntry(
            date: date,
            state: state,
            displayed: state.displayedValue(at: date, boosts: boosts)
        )
    }
}

// MARK: - Entry view

struct MochiWidgetEntryView: View {
    let entry: MochiEntry

    @Environment(\.widgetFamily) private var family

    private var theme: MochiTheme {
        MochiTheme.theme(id: entry.state?.themeId ?? MochiTheme.sesame.id)
    }

    /// Lapsed sleeps, vacation rests (both calm, never conflated in copy);
    /// active shows the forecast mood.
    private var mood: MochiMood {
        switch entry.state?.displayState {
        case .lapsed, .vacation: .sleeping
        default: MochiMood(vitality: entry.displayed)
        }
    }

    private var nextTask: MochiWidgetState.NextTask? {
        entry.state?.nextTasks.first
    }

    private func taskTitle(_ task: MochiWidgetState.NextTask) -> String {
        entry.state?.hideTaskNames == true ? "A task" : task.title
    }

    private func dueText(_ task: MochiWidgetState.NextTask) -> String {
        guard let dueAt = task.dueAt else { return "someday" }
        if task.hasTime {
            return dueAt.formatted(date: .omitted, time: .shortened)
        }
        return Calendar.current.isDateInToday(dueAt)
            ? "today"
            : dueAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private var moodLabel: String {
        switch entry.state?.displayState {
        case .lapsed: return "napping"
        case .vacation: return "resting"
        default: break
        }
        switch MoodBand(value: entry.displayed) {
        case .verySad: return "very sad"
        case .anxious: return "anxious"
        case .uneasy: return "uneasy"
        case .content: return "content"
        case .happy: return "happy"
        case .ecstatic: return "ecstatic"
        }
    }

    var body: some View {
        switch family {
        case .systemSmall: smallView
        case .systemMedium: mediumView
        case .accessoryCircular: circularView
        case .accessoryRectangular: rectangularView
        default: inlineView
        }
    }

    // MARK: Home screen

    private var smallView: some View {
        VStack(spacing: 2) {
            petButton(size: 74)
            Text("Mochi is \(moodLabel)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            statusLine
        }
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                petButton(size: 78)
                Text("Mochi is \(moodLabel)")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 5) {
                switch entry.state?.displayState {
                case .vacation:
                    Text("On vacation")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(theme.ink)
                    Text(vacationBackText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.muted)
                case .lapsed:
                    Text("Mochi is napping")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(theme.ink)
                    Text("Wake Mochi")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(theme.primaryText)
                default:
                    Text("Next up")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(theme.muted)
                        .textCase(.uppercase)
                }
                if let task = nextTask {
                    HStack(spacing: 8) {
                        if task.completable, entry.state?.displayState != .vacation {
                            Button(intent: CompleteTaskIntent(taskId: task.id)) {
                                Image(systemName: "circle")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(theme.primaryText)
                            }
                            .buttonStyle(.plain)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(taskTitle(task))
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                .foregroundStyle(theme.ink)
                                .lineLimit(1)
                            Text(dueText(task))
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundStyle(theme.muted)
                        }
                    }
                } else if entry.state?.displayState == .active {
                    Text("All clear. A calm day.")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var vacationBackText: String {
        guard let end = entry.state?.vacationEnd else { return "back whenever you're ready" }
        return "back \(end.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
    }

    private var statusLine: some View {
        Group {
            switch entry.state?.displayState {
            case .lapsed:
                Text("Wake Mochi")
                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.primaryText)
            case .vacation:
                Text(vacationBackText)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.muted)
            default:
                if let task = nextTask {
                    Text(taskTitle(task))
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.muted)
                        .lineLimit(1)
                }
            }
        }
    }

    /// Tap-to-pet on the home screen (active only) - the buffer lift runs
    /// entirely inside the App Group, no sync, instant reload.
    private func petButton(size: CGFloat) -> some View {
        Group {
            if entry.state?.displayState == .active {
                Button(intent: PetMochiIntent()) {
                    petImage(size: size)
                }
                .buttonStyle(.plain)
            } else {
                petImage(size: size)
            }
        }
    }

    /// Rendered to a static image and marked full-color so mood survives
    /// iOS 26's Liquid-Glass tinting (mood is partly carried by color).
    private func petImage(size: CGFloat) -> some View {
        let renderer = ImageRenderer(
            content: MochiPetView(mood: mood, size: size, showsSparkles: false)
                .environment(\.mochiTheme, theme)
        )
        renderer.scale = 3
        return Group {
            if let image = renderer.uiImage {
                Image(uiImage: image)
                    .widgetAccentedRenderingMode(.fullColor)
            } else {
                MochiPetView(mood: mood, size: size, showsSparkles: false)
                    .environment(\.mochiTheme, theme)
            }
        }
    }

    // MARK: Lock screen (system renders these monochrome)

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            MochiPetView(mood: mood, size: 40, showsSparkles: false)
                .environment(\.mochiTheme, theme)
        }
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Mochi is \(moodLabel)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
            if let task = nextTask {
                Text(taskTitle(task))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(dueText(task))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inlineView: some View {
        // One line, next task only, no Mochi (design doc).
        Group {
            if let task = nextTask {
                Text("\(taskTitle(task)) · \(dueText(task))")
            } else {
                Text("Mochi is \(moodLabel)")
            }
        }
    }
}
