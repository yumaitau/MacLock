//
//  LaunchAtLogin.swift
//  MacLock
//

import OSLog
import ServiceManagement

/// Registers MacLock as a login item.
///
/// The system is the source of truth: `isEnabled` reads the live registration state
/// rather than a stored flag, so the toggle can never show something the system
/// disagrees with.
@MainActor
enum LaunchAtLogin {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters, returning whether the system accepted the change.
    ///
    /// Registration genuinely fails for an unsigned or relocated build, so callers
    /// revert their toggle on `false` instead of showing a state that is not real.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return true }
                try SMAppService.mainApp.register()
            } else {
                guard SMAppService.mainApp.status == .enabled else { return true }
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            // Keep a trail: registration failures happen on unsigned or relocated
            // builds and are awkward to reproduce on demand.
            Logger(subsystem: "au.com.yumait.MacLock", category: "LaunchAtLogin")
                .error("Failed to \(enabled ? "register" : "unregister") the login item: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
