import SwiftUI
import WidgetKit
import ActivityKit

private struct StudyEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> StudyEntry { StudyEntry(date: Date(), snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (StudyEntry) -> Void) { completion(read()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StudyEntry>) -> Void) {
        completion(Timeline(entries: [read()], policy: .after(Date().addingTimeInterval(1800))))
    }
    private func read() -> StudyEntry {
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.app.renalik.mnemo")?.appendingPathComponent("snapshot.json")
        let snapshot = url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(WidgetSnapshot.self, from: $0) }
        return StudyEntry(date: Date(), snapshot: snapshot)
    }
}

private struct MnemoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StudyEntry
    private var russian: Bool { entry.snapshot?.language != "en" }
    private var due: String { entry.snapshot.map { "\($0.due)" } ?? "—" }
    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 2) { Image(systemName: "rectangle.on.rectangle"); Text(due).font(.headline) }
            case .accessoryInline:
                Text(russian ? "Mnemo · повторить: \(due)" : "Mnemo · due: \(due)")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 3) {
                    Label("Mnemo", systemImage: "rectangle.on.rectangle")
                    Text(russian ? "К повтору: \(due)" : "Due: \(due)").font(.headline)
                }
            default:
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Label("Mnemo", systemImage: "rectangle.on.rectangle").font(.headline); Spacer(); Image(systemName: "sparkle") }
                    Text(due).font(.system(size: 42, weight: .semibold, design: .rounded))
                    Text(entry.snapshot == nil ? (russian ? "Откройте приложение" : "Open the app") : (russian ? "карточек к повторению" : "cards ready to review")).font(.caption)
                    if family == .systemMedium, let snapshot = entry.snapshot {
                        HStack { Text(russian ? "Повторено: \(snapshot.reviewed)" : "Reviewed: \(snapshot.reviewed)"); Spacer(); Label("\(snapshot.streak)", systemImage: "flame.fill") }.font(.caption)
                    }
                }.foregroundStyle(.white)
            }
        }.widgetURL(URL(string: "mnemo://review"))
            .containerBackground(for: .widget) { Color(red: 0.12, green: 0.08, blue: 0.04).overlay(alignment: .topTrailing) { Circle().fill(.orange.opacity(0.5)).blur(radius: 35).offset(x: 25, y: -35) } }
    }
}

struct MnemoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MnemoToday", provider: Provider()) { entry in MnemoWidgetView(entry: entry) }
            .configurationDisplayName("Mnemo").description("Карточки на сегодня / Today's cards")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

struct MnemoLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StudyAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Mnemo", systemImage: "rectangle.on.rectangle")
                    Spacer()
                    Text("\(context.state.completed) / \(context.state.total)").monospacedDigit()
                }.font(.headline)
                ProgressView(value: Double(context.state.completed), total: Double(max(1, context.state.total))).tint(.orange)
                Text(context.state.started, style: .timer).font(.caption)
            }.padding(20).activityBackgroundTint(.black.opacity(0.9)).activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label("Mnemo", systemImage: "rectangle.on.rectangle").font(.headline) }
                DynamicIslandExpandedRegion(.trailing) { Text("\(context.state.completed)/\(context.state.total)").monospacedDigit() }
                DynamicIslandExpandedRegion(.bottom) { ProgressView(value: Double(context.state.completed), total: Double(max(1, context.state.total))).tint(.orange) }
            } compactLeading: {
                Image(systemName: "rectangle.on.rectangle").foregroundStyle(.orange)
            } compactTrailing: {
                Text("\(context.state.completed)/\(context.state.total)").font(.caption2).monospacedDigit()
            } minimal: {
                Image(systemName: "rectangle.on.rectangle").foregroundStyle(.orange)
            }
            .widgetURL(URL(string: "mnemo://review")).keylineTint(.orange)
        }
    }
}

@main struct MnemoWidgetBundle: WidgetBundle {
    var body: some Widget { MnemoWidget(); MnemoLiveActivity() }
}
