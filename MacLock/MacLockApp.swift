//
//  MacLockApp.swift
//  MacLock
//
//  Created by Josh Luongo on 25/8/2026.
//

import SwiftUI

@main
struct MacLockApp: App {
    @State private var settings: AppSettings
    @State private var screenLocker: ScreenLocker
    @State private var monitor: WatchMonitor
    @State private var wifi: WiFiMonitor
    @State private var controller: MacLockController

    init() {
        let settings = AppSettings()
        let monitor = WatchMonitor()
        let screenLocker = ScreenLocker()
        let wifi = WiFiMonitor()
        let controller = MacLockController(
            settings: settings,
            monitor: monitor,
            screenLocker: screenLocker,
            wifi: wifi
        )

        _settings = State(initialValue: settings)
        _monitor = State(initialValue: monitor)
        _screenLocker = State(initialValue: screenLocker)
        _wifi = State(initialValue: wifi)
        _controller = State(initialValue: controller)

        // The app has no window to hang an onAppear from, so monitoring starts here.
        controller.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                settings: settings,
                controller: controller,
                screenLocker: screenLocker
            )
        } label: {
            Self.menuBarIcon(
                named: controller.status.imageName,
                dimmed: !controller.status.isGuarding
            )
            .accessibilityLabel(controller.status.label)
        }

        Settings {
            SettingsView(
                settings: settings,
                monitor: monitor,
                wifi: wifi,
                controller: controller
            )
        }
    }

    /// Standard menu bar glyph height. The artwork is drawn on a 30pt canvas, which
    /// towers over neighbouring items if used at its natural size.
    private static let menuBarIconSize = NSSize(width: 18, height: 18)

    /// How much of full strength a non-guarding icon is drawn at.
    private static let dimmedFraction: CGFloat = 0.45

    /// Loads a menu bar icon at the right size, optionally dimmed.
    ///
    /// Both the size and the dimming have to be baked into the `NSImage`:
    /// `MenuBarExtra` renders its label into the status item and ignores SwiftUI
    /// `.frame` and `.opacity` modifiers on it.
    private static func menuBarIcon(named name: String, dimmed: Bool) -> Image {
        guard let base = NSImage(named: name)?.copy() as? NSImage else {
            // Never leave the menu bar blank if an asset goes missing.
            return Image(systemName: "exclamationmark.triangle")
        }
        base.size = menuBarIconSize

        guard dimmed else {
            base.isTemplate = true
            return Image(nsImage: base)
        }

        let faded = NSImage(size: menuBarIconSize, flipped: false) { rect in
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: dimmedFraction)
            return true
        }
        faded.isTemplate = true
        return Image(nsImage: faded)
    }
}
