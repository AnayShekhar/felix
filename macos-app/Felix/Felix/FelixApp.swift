import SwiftUI

@main
struct FelixApp: App {
    @StateObject private var env = AppEnvironment()
    @Environment(\.openWindow) private var openWindow

    init() {
        Notifier.requestAuthorization()
    }

    var body: some Scene {
        // Menu bar item only (no Dock icon — LSUIElement = YES in Info.plist).
        MenuBarExtra {
            MenuBarPopover()
                .environmentObject(env)
        } label: {
            Image(systemName: "waveform.circle")
        }
        .menuBarExtraStyle(.window)

        // The dashboard window — opened from the popover or ⌘⇧F.
        Window("Felix Dashboard", id: "dashboard") {
            DashboardView()
                .environmentObject(env)
                .frame(minWidth: 700, minHeight: 500)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 900, height: 600)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Dashboard") { openWindow(id: "dashboard") }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }
    }
}
