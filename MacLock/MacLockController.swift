//
//  MacLockController.swift
//  MacLock
//

import AppKit
import Foundation
import OSLog

/// Drives monitoring: feeds samples into the proximity engine, acts on its lock
/// decisions, and publishes the state the menu bar shows.
///
/// A single one-second timer reconciles settings and advances the engine's clock.
/// Using one timer for both means the no-signal timeout can fire when no sample
/// arrives at all, which is the whole point of that timeout.
@Observable
@MainActor
final class MacLockController {

    /// What MacLock is doing right now. `cannotMonitor` is a first-class state, not
    /// a variant of `away`: it means MacLock has no evidence about where the user
    /// is, and locking on no evidence is the failure this app must not have.
    enum Status: Equatable {
        case cannotLock(String)
        case cannotMonitor(String)
        case noDevice
        case paused
        case onTrustedNetwork(String)
        case locked
        case away
        case inRange
        case waitingForSignal

        /// Name of the asset-catalogue image for this state. Both are template
        /// images, so the menu bar tints them for the current appearance.
        var imageName: String {
            switch self {
            case .cannotLock, .cannotMonitor: "Error"
            default: "Menu"
            }
        }

        /// Whether MacLock is actually watching the watch right now.
        ///
        /// The icon is dimmed when it is not, so a paused or unconfigured MacLock
        /// never looks like it is guarding the Mac. That is the same principle the
        /// monitoring gate enforces, carried through to what the user can see.
        var isGuarding: Bool {
            switch self {
            case .inRange, .away, .locked, .waitingForSignal: true
            case .cannotLock, .cannotMonitor, .noDevice, .paused, .onTrustedNetwork: false
            }
        }

        var label: String {
            switch self {
            case .cannotLock(let reason): "Cannot lock this Mac: \(reason)"
            case .cannotMonitor(let reason): reason
            case .noDevice: "No watch selected"
            case .paused: "Monitoring paused"
            case .onTrustedNetwork(let name): "On \"\(name)\" - not watching"
            case .locked: "Locked"
            case .away: "Watch is away"
            case .inRange: "Watch is nearby"
            case .waitingForSignal: "Looking for your watch"
            }
        }

        /// A short name for the log, carrying no user data -- no network name, no
        /// system message. It makes the decision trail readable after the fact
        /// without recording where this Mac has been.
        var logDescription: String {
            switch self {
            case .cannotLock: "cannotLock"
            case .cannotMonitor: "cannotMonitor"
            case .noDevice: "noDevice"
            case .paused: "paused"
            case .onTrustedNetwork: "onTrustedNetwork"
            case .locked: "locked"
            case .away: "away"
            case .inRange: "inRange"
            case .waitingForSignal: "waitingForSignal"
            }
        }
    }

    private let settings: AppSettings
    private let monitor: WatchMonitor
    private let screenLocker: ScreenLocker
    private let wifi: WiFiMonitor

    /// Why MacLock started or stopped watching, and every lock it asked for. A
    /// utility that locks your Mac on its own should be able to answer "why did it
    /// do that" afterwards, not only while someone is looking at the menu bar.
    ///
    /// Logged at notice rather than info: info is held in memory and dropped, so a
    /// trail meant to be read after the fact has to be at a level the system keeps.
    private let log = Logger(subsystem: "au.com.yumait.MacLock", category: "Monitoring")
    private var lastLoggedStatus: Status?

    private var engine: ProximityEngine
    private var timer: Timer?
    private var isSampling = false
    private var wakeObserver: (any NSObjectProtocol)?

    /// Tracks the observed lock state so the moment of unlocking can be spotted.
    private var wasScreenLocked = false

    private(set) var status: Status = .waitingForSignal

    /// Smoothed signal in dBm, which is what the lock decision actually uses. The
    /// calibration slider shows this rather than the raw reading, which jitters too
    /// much to aim at.
    private(set) var smoothedRSSI: Int?

    init(
        settings: AppSettings,
        monitor: WatchMonitor,
        screenLocker: ScreenLocker,
        wifi: WiFiMonitor
    ) {
        self.settings = settings
        self.monitor = monitor
        self.screenLocker = screenLocker
        self.wifi = wifi
        self.engine = ProximityEngine(configuration: settings.proximityConfiguration)

        monitor.onSample = { [weak self] rssi, time in
            self?.handleSample(rssi: rssi, at: time)
        }
    }

    func start() {
        guard timer == nil else { return }
        observeWake()
        wasScreenLocked = screenLocker.screenIsLocked
        tick()

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        stopSampling()
    }

    private func handleSample(rssi: Int, at time: Date) {
        engine.screenIsLocked = screenLocker.screenIsLocked
        let decision = engine.record(rssi: rssi, at: time)
        smoothedRSSI = engine.smoothedRSSI
        act(on: decision)
        updateStatus()
    }

    /// Clears the sample history when the Mac wakes.
    ///
    /// Without this, a Mac that slept overnight wakes with a sample timestamp hours
    /// old, and the very first tick - which runs before the watch has been heard
    /// again - sees the no-signal timeout already exceeded and re-locks the Mac the
    /// instant the user unlocks it.
    private func observeWake() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resetHistory() }
        }
    }

    private func resetHistory() {
        engine.reset()
        smoothedRSSI = nil
    }

    private func tick() {
        engine.configuration = settings.proximityConfiguration

        // One clock drives every periodic read, so the Wi-Fi network and the
        // proximity decision within a tick always describe the same moment.
        wifi.refresh()

        // Unlocking means the user is back, so the dwell starts fresh. This also
        // covers a wake that never locked the screen.
        let locked = screenLocker.screenIsLocked
        if wasScreenLocked && !locked {
            resetHistory()
        }
        wasScreenLocked = locked
        engine.screenIsLocked = locked

        reconcileSampling()

        if isSampling {
            act(on: engine.tick(at: Date()))
        }
        updateStatus()
    }

    /// Brings sampling into line with the current settings.
    ///
    /// Sampling stops whenever MacLock has no business watching: it cannot lock at
    /// all, no device is chosen, or the user paused it. Restarting always resets the
    /// engine, so a reading from before a pause, a device change or a system sleep
    /// can never fire an immediate lock.
    private func reconcileSampling() {
        guard case .monitor = monitoringDecision(currentInputs) else {
            stopSampling()
            return
        }

        // The gate already established that a device is selected; this is the
        // unwrap, not a second check.
        guard let deviceID = settings.selectedDeviceID else { return }

        if !isSampling {
            engine.reset()
            smoothedRSSI = nil
            isSampling = true
        }
        monitor.startSampling(deviceID: deviceID, passive: settings.usePassiveMode)
    }

    private func stopSampling() {
        guard isSampling else { return }
        monitor.stopSampling()
        engine.reset()
        smoothedRSSI = nil
        isSampling = false
    }

    private func act(on decision: LockReason?) {
        guard let decision else { return }
        log.notice("Locking the screen: \(String(describing: decision), privacy: .public)")
        screenLocker.lock()
    }

    /// The observable facts the monitoring gate decides from.
    private var currentInputs: MonitoringInputs {
        MonitoringInputs(
            canLock: screenLocker.availability == .available,
            hasDevice: settings.selectedDeviceID != nil,
            isPaused: settings.isPaused,
            onTrustedNetwork: isOnTrustedNetwork(
                ssid: wifi.network.ssid,
                trusted: settings.trustedNetworks
            ),
            bluetoothAvailable: monitor.unavailability == nil
        )
    }

    private func updateStatus() {
        // The icon reports the same precedence the gate decides by, so the most
        // fundamental problem is the one shown.
        if case .standDown(let reason) = monitoringDecision(currentInputs) {
            switch reason {
            case .cannotLock:
                let detail: String
                if case .unavailable(let message) = screenLocker.availability { detail = message } else { detail = "" }
                status = .cannotLock(detail)
            case .noDevice:
                status = .noDevice
            case .paused:
                status = .paused
            case .trustedNetwork:
                // The gate only reaches here on a name that matched a trusted entry,
                // so there is a name to show.
                status = .onTrustedNetwork(wifi.network.ssid ?? "")
            case .cannotMonitor:
                status = .cannotMonitor(monitor.unavailability?.message ?? "")
            }
        } else if screenLocker.screenIsLocked {
            status = .locked
        } else if smoothedRSSI == nil {
            status = .waitingForSignal
        } else if engine.state == .away || engine.state == .signalLost {
            status = .away
        } else {
            status = .inRange
        }

        if status != lastLoggedStatus {
            lastLoggedStatus = status
            let description = status.logDescription
            log.notice("Monitoring state: \(description, privacy: .public)")
        }
    }
}
