import SwiftUI
import AppKit

@main
struct LumisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var env = AppEnvironment()
    @StateObject private var auth = AuthStore()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Menu bar item only (no Dock icon — LSUIElement = YES in Info.plist).
        // Template rendering keeps the glyph visible on both light and dark
        // menu bars (it was rendering white-on-white before).
        MenuBarExtra {
            MenuBarPopover { openDashboard() }
                .environmentObject(env)
                .environmentObject(auth)
        } label: {
            Image(systemName: "waveform")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)

        // The dashboard window — opened from the popover or ⌘⇧F.
        Window("Lumis", id: WindowID.dashboard) {
            Group {
                if auth.booting {
                    ProgressView().controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DashboardBackground())
                } else if auth.isAuthenticated {
                    DashboardView().environmentObject(env)
                } else {
                    LoginView()
                }
            }
                .environmentObject(auth)
                .task { await auth.bootstrap() }
                .frame(minWidth: 760, minHeight: 520)
                // Promote the app to a regular (Dock-visible) app while the
                // window is up, then drop back to accessory when it closes —
                // an LSUIElement app otherwise can't bring a window to front.
                .onAppear { AppDelegate.activateWindowMode() }
                .onDisappear { AppDelegate.deactivateWindowMode() }
        }
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Dashboard") { openDashboard() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }
    }

    /// Opens (or focuses) the dashboard and pulls it to the foreground.
    private func openDashboard() {
        AppDelegate.activateWindowMode()
        openWindow(id: WindowID.dashboard)
    }
}

enum WindowID {
    static let dashboard = "dashboard"
}

/// Manages the LSUIElement → regular activation handoff so the dashboard window
/// reliably appears and takes focus.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.requestAuthorization()
        NSApp.setActivationPolicy(.accessory)
    }

    /// Become a regular app and bring the window forward.
    static func activateWindowMode() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Defer so the window exists before we order it front.
        DispatchQueue.main.async {
            NSApp.windows
                .first { $0.identifier?.rawValue.contains(WindowID.dashboard) == true || $0.canBecomeMain }?
                .makeKeyAndOrderFront(nil)
        }
    }

    /// Drop back to a menu-bar-only accessory app once the window is gone.
    static func deactivateWindowMode() {
        // Only revert if no visible standard windows remain.
        let hasVisibleWindow = NSApp.windows.contains {
            $0.isVisible && $0.styleMask.contains(.titled)
        }
        if !hasVisibleWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
