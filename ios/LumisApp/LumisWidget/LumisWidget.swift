import WidgetKit
import SwiftUI

/// Phase 8 — Lumis lock-screen widget (accessoryCircular).
///
/// Shows a waveform glyph in Lumis amber on a dark background. Tapping it
/// deep-links to `lumis://capture`, which the main app handles by arming the mic.
/// The timeline refreshes every 15 minutes (the glyph is static, but a periodic
/// reload keeps the complication fresh on the lock screen).

private let lumisAmber = Color(red: 0.961, green: 0.620, blue: 0.129)

struct LumisEntry: TimelineEntry {
    let date: Date
}

struct LumisProvider: TimelineProvider {
    func placeholder(in context: Context) -> LumisEntry {
        LumisEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (LumisEntry) -> Void) {
        completion(LumisEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LumisEntry>) -> Void) {
        let now = Date()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        let timeline = Timeline(entries: [LumisEntry(date: now)], policy: .after(next))
        completion(timeline)
    }
}

struct LumisWidgetEntryView: View {
    var entry: LumisEntry

    var body: some View {
        ZStack {
            // accessoryWidgetBackground gives the system lock-screen tint.
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: "waveform.circle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(lumisAmber)
                Text("Lumis")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
        .widgetURL(URL(string: "lumis://capture"))
    }
}

@main
struct LumisWidget: Widget {
    let kind = "LumisWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LumisProvider()) { entry in
            LumisWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Lumis")
        .description("Tap to talk to Lumis.")
        .supportedFamilies([.accessoryCircular])
    }
}

#Preview(as: .accessoryCircular) {
    LumisWidget()
} timeline: {
    LumisEntry(date: .now)
}
