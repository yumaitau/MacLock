//
//  AppSettings.swift
//  MacLock
//

import Foundation

/// Everything the user can configure, persisted in `UserDefaults`.
///
/// This is the single source of truth for configuration: nothing else reads these
/// keys directly.
@Observable
@MainActor
final class AppSettings {

    private enum Key {
        static let selectedDeviceID = "selectedDeviceID"
        static let selectedDeviceName = "selectedDeviceName"
        static let lockThreshold = "lockThreshold"
        static let awayDelay = "awayDelay"
        static let noSignalTimeout = "noSignalTimeout"
        static let usePassiveMode = "usePassiveMode"
        static let isPaused = "isPaused"
        static let launchAtLogin = "launchAtLogin"
    }

    /// First-run values. The threshold in particular is only a starting point --
    /// the user calibrates it against the live readout.
    enum Defaults {
        static let lockThreshold = -75
        static let awayDelay: TimeInterval = 5
        static let noSignalTimeout: TimeInterval = 30
    }

    /// Bounds that keep a hand-edited or corrupt preferences file from producing
    /// behaviour the user cannot recover from through the UI.
    enum Limits {
        static let threshold = -100...(-40)
        static let awayDelay: ClosedRange<TimeInterval> = 0...120
        static let noSignalTimeout: ClosedRange<TimeInterval> = 5...300
    }

    private let defaults: UserDefaults

    /// Identifier of the watch being monitored, or `nil` when none is chosen.
    var selectedDeviceID: UUID? {
        didSet { defaults.set(selectedDeviceID?.uuidString, forKey: Key.selectedDeviceID) }
    }

    /// Display name of the selected device, kept so the menu can name it before
    /// Bluetooth has rediscovered the peripheral.
    var selectedDeviceName: String? {
        didSet { defaults.set(selectedDeviceName, forKey: Key.selectedDeviceName) }
    }

    /// Smoothed RSSI at or above which the watch counts as in range, in dBm.
    var lockThreshold: Int {
        didSet { defaults.set(lockThreshold, forKey: Key.lockThreshold) }
    }

    /// Seconds the smoothed signal must stay below the threshold before locking.
    var awayDelay: TimeInterval {
        didSet { defaults.set(awayDelay, forKey: Key.awayDelay) }
    }

    /// Seconds of silence before locking.
    var noSignalTimeout: TimeInterval {
        didSet { defaults.set(noSignalTimeout, forKey: Key.noSignalTimeout) }
    }

    /// Observe advertisements instead of connecting and polling. Slower to update,
    /// but it does not disturb other Bluetooth peripherals.
    var usePassiveMode: Bool {
        didSet { defaults.set(usePassiveMode, forKey: Key.usePassiveMode) }
    }

    /// Monitoring suspended by the user. Persisted so a pause survives a relaunch.
    var isPaused: Bool {
        didSet { defaults.set(isPaused, forKey: Key.isPaused) }
    }

    /// Mirrors the login-item registration. `LaunchAtLogin` owns the system side.
    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.selectedDeviceID = (defaults.string(forKey: Key.selectedDeviceID)).flatMap(UUID.init(uuidString:))
        self.selectedDeviceName = defaults.string(forKey: Key.selectedDeviceName)

        let storedThreshold = defaults.object(forKey: Key.lockThreshold) as? Int ?? Defaults.lockThreshold
        self.lockThreshold = storedThreshold.clamped(to: Limits.threshold)

        let storedAway = defaults.object(forKey: Key.awayDelay) as? TimeInterval ?? Defaults.awayDelay
        self.awayDelay = storedAway.clamped(to: Limits.awayDelay)

        let storedTimeout = defaults.object(forKey: Key.noSignalTimeout) as? TimeInterval ?? Defaults.noSignalTimeout
        self.noSignalTimeout = storedTimeout.clamped(to: Limits.noSignalTimeout)

        self.usePassiveMode = defaults.bool(forKey: Key.usePassiveMode)
        self.isPaused = defaults.bool(forKey: Key.isPaused)
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
    }

    /// The tuning values in the shape the proximity engine wants.
    var proximityConfiguration: ProximityConfiguration {
        ProximityConfiguration(
            lockThreshold: lockThreshold,
            awayDelay: awayDelay,
            noSignalTimeout: noSignalTimeout
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
