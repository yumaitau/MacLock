//
//  AppUpdater.swift
//  MacLock
//

import Foundation
import Sparkle

/// Owns the Sparkle updater and exposes the two things the interface needs from it:
/// whether a check can be started right now, and whether checks happen on their own.
///
/// Sparkle is configured from `Info.plist` -- the feed URL, the public signing key,
/// and that scheduled checks are on by default -- and it persists what the user
/// changes in its own `UserDefaults` keys. So there is deliberately no mirror of any
/// of that in `AppSettings`: Sparkle is the source of truth, and this class only
/// hands its state to SwiftUI in a shape it can observe.
@Observable
@MainActor
final class AppUpdater {

    /// Whether a user-initiated check may start. False while a check or an install
    /// is already under way, which is when a second click would only produce a
    /// second alert.
    private(set) var canCheckForUpdates = false

    /// Whether Sparkle checks on its own schedule. Read from Sparkle at launch and
    /// written straight back to it, so the toggle in Settings and Sparkle's own
    /// record of the choice can never disagree.
    var automaticallyChecksForUpdates: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }

    /// The version as the user would quote it in a bug report: "1.2 (7)".
    let currentVersion: String

    /// Display version of an update a scheduled check found and Sparkle is holding
    /// back, or `nil` when there is none.
    ///
    /// Sparkle shows a scheduled update's alert behind other windows so as not to
    /// interrupt, and for a menu bar app with no windows of its own that alert can go
    /// unnoticed indefinitely. So Sparkle is told this app provides its own gentle
    /// reminder: the panel shows an "update available" row while this is set, and
    /// choosing it brings Sparkle's alert forward. Sparkle still shows the alert
    /// itself, in focus, for an update found right after launch.
    private(set) var pendingUpdateVersion: String?

    private let controller: SPUStandardUpdaterController

    /// The object Sparkle talks to about scheduled updates. Separate from this class
    /// so it can be handed to the controller before `self` is fully initialised.
    private let reminder = ScheduledUpdateReminder()

    /// Keeps the KVO subscription alive for as long as the updater is.
    private var canCheckObservation: NSKeyValueObservation?

    init() {
        // Starting the updater here is what schedules the background checks. The
        // standard controller also supplies Sparkle's own alerts, which activate
        // this windowless app so the user can see them.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: reminder
        )
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        currentVersion = Self.versionString(from: Bundle.main)

        reminder.onUpdateHeld = { [weak self] version in self?.pendingUpdateVersion = version }
        reminder.onSessionFinished = { [weak self] in self?.pendingUpdateVersion = nil }

        canCheckObservation = controller.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, change in
            // Sparkle publishes this on the main thread; the assertion documents
            // that rather than hoping.
            MainActor.assumeIsolated {
                self?.canCheckForUpdates = change.newValue ?? updater.canCheckForUpdates
            }
        }
    }

    /// A check the user asked for. Unlike a scheduled check it always ends in an
    /// alert -- an update, "you're up to date", or the error that stopped it.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    private static func versionString(from bundle: Bundle) -> String {
        let marketing = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(marketing) (\(build))"
    }
}

/// Sparkle's standard-user-driver delegate, implementing "gentle reminders" for
/// scheduled updates: Sparkle keeps the alert back and tells us, and we surface it
/// in the panel instead. Sparkle calls these on the main thread.
@MainActor
private final class ScheduledUpdateReminder: NSObject, SPUStandardUserDriverDelegate {

    var onUpdateHeld: ((String) -> Void)?
    var onSessionFinished: (() -> Void)?

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Let Sparkle show the alert itself when it wants it in immediate focus -- an
    /// update found right after launch -- and hold everything else for the panel.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        // Sparkle shows what it said it would; only a held update needs the reminder.
        guard !handleShowingUpdate else { return }
        let version = update.displayVersionString
        MainActor.assumeIsolated { onUpdateHeld?(version) }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { onSessionFinished?() }
    }
}
