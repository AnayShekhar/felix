import Foundation
import ServiceManagement

/// Wraps SMAppService for the "Launch at login" toggle in Settings.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns true on success; on failure the caller surfaces the message inline.
    @discardableResult
    static func set(_ enabled: Bool) -> (ok: Bool, message: String?) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
