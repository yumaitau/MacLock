//
//  MenuBarContent.swift
//  MacLock
//

import AppKit
import SwiftUI

/// The menu behind the status icon.
struct MenuBarContent: View {
    @Bindable var settings: AppSettings
    var controller: MacLockController
    var screenLocker: ScreenLocker

    var body: some View {
        Text(controller.status.label)

        Divider()

        Toggle("Pause Monitoring", isOn: $settings.isPaused)

        Button("Lock Screen Now") {
            screenLocker.lock()
        }
        .disabled(screenLocker.availability != .available)

        Divider()

        SettingsLink {
            Text("Settings...")
        }

        Button("Quit MacLock") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
