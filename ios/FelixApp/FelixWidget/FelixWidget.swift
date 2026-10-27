import WidgetKit
import SwiftUI

/// Phase 8 — Felix lock-screen widget (accessoryCircular).
///
/// Shows a waveform glyph in Felix amber on a dark background. Tapping it
/// deep-links to `felix://capture`, which the main app handles by arming the mic.
/// The timeline refreshes every 15 minutes (the glyph is static, but a periodic
/// reload keeps the complication fresh on the lock screen).

private let felixAmber = Color(red: 0.961, green: 0.620, blue: 0.129)

struct FelixEntry: TimelineEntry {
    let date: Date
}

struct FelixProvider: TimelineProvider {
    func placeholder(in context: Context) -> FelixEntry {
        FelixEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (FelixEntry) -> Void) {
        completion(FelixEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FelixEntry>) -> Void) {
        let now = Date()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        let timeline = Timeline(entries: [FelixEntry(date: now)], policy: .after(next))
        completion(timeline)
    }
}

struct FelixWidgetEntryView: View {
    var entry: FelixEntry

    var body: some View {
        ZStack {
            // accessoryWidgetBackground gives the system lock-screen tint.
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: "waveform.circle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(felixAmber)
                Text("Felix")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
        .widgetURL(URL(string: "felix://capture"))
    }
}

@main
struct FelixWidget: Widget {
    let kind = "FelixWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FelixProvider()) { entry in
            FelixWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Felix")
        .description("Tap to talk to Felix.")
        .supportedFamilies([.accessoryCircular])
    }
}

#Preview(as: .accessoryCircular) {
    FelixWidget()
} timeline: {
    FelixEntry(date: .now)
}
