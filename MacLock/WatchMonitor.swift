//
//  WatchMonitor.swift
//  MacLock
//

import CoreBluetooth
import Foundation

/// Discovers nearby Bluetooth devices and tracks the signal strength of the one
/// the user selected.
///
/// The central manager is created on the main queue, so every delegate callback
/// arrives on the main actor. The callbacks are declared `nonisolated` to satisfy
/// the Objective-C protocol and immediately re-enter the main actor.
@Observable
@MainActor
final class WatchMonitor: NSObject {

    /// A device seen during a scan.
    struct DiscoveredDevice: Identifiable, Equatable {
        let id: UUID
        var name: String
        var rssi: Int
        var lastSeen: Date
    }

    /// Why monitoring is not currently possible, if it is not.
    enum Unavailability: Equatable {
        case bluetoothOff
        case unauthorised
        case unsupported
        case starting

        var message: String {
            switch self {
            case .bluetoothOff: "Bluetooth is switched off. Turn it on to find your watch."
            case .unauthorised: "MacLock is not allowed to use Bluetooth. Grant access in System Settings > Privacy & Security > Bluetooth."
            case .unsupported: "This Mac does not support Bluetooth Low Energy."
            case .starting: "Starting Bluetooth..."
            }
        }
    }

    /// `nil` when Bluetooth is ready; otherwise why it is not.
    private(set) var unavailability: Unavailability? = .starting

    /// Devices found in the current scan, ordered by name. Refreshed on a timer
    /// rather than per advertisement so a busy radio cannot drive the UI.
    private(set) var discovered: [DiscoveredDevice] = []

    /// Latest signal strength for the selected device, or `nil` if not heard yet.
    private(set) var selectedRSSI: Int?

    /// Called for every sample of the selected device. The controller feeds these
    /// into the proximity engine.
    var onSample: ((Int, Date) -> Void)?

    private var central: CBCentralManager!
    private var seen: [UUID: DiscoveredDevice] = [:]
    private var refreshTimer: Timer?

    /// The Settings window wants a live device list.
    private var isDiscovering = false

    /// Sampling state for the selected device.
    private var sampledDeviceID: UUID?
    private var usePassiveMode = false
    private var sampledPeripheral: CBPeripheral?
    private var pollTimer: Timer?

    /// How often the connected peripheral's signal is polled in active mode.
    private static let pollInterval: TimeInterval = 1.0

    /// How often the published device list is rebuilt while scanning.
    private static let refreshInterval: TimeInterval = 0.25

    /// A device not heard from for this long drops out of the scan list. Kept
    /// generous so intermittent trackers do not flicker in and out of the list and
    /// shift the row the user is reaching for. Liveness of the *selected* device is
    /// tracked separately and is not affected by this.
    private static let staleAfter: TimeInterval = 30

    override init() {
        super.init()
        // queue: nil means the main queue, so delegate callbacks land on the main actor.
        central = CBCentralManager(delegate: self, queue: nil)
    }

    /// Begins listing nearby devices for the Settings window. Safe to call repeatedly.
    func startScanning() {
        isDiscovering = true
        updateScanState()
    }

    func stopScanning() {
        isDiscovering = false
        updateScanState()
    }

    /// Begins sampling the selected device's signal.
    ///
    /// Active mode connects and polls; passive mode reads the signal off ordinary
    /// advertisements. Both produce the same stream of timestamped samples, so
    /// nothing downstream needs to know which is running.
    func startSampling(deviceID: UUID, passive: Bool) {
        if sampledDeviceID == deviceID && usePassiveMode == passive { return }

        // Tear the previous path down completely. Leaving a connection open while
        // scanning is exactly the interference the passive toggle exists to avoid.
        stopSampling()

        sampledDeviceID = deviceID
        usePassiveMode = passive
        beginSampling()
    }

    func stopSampling() {
        pollTimer?.invalidate()
        pollTimer = nil

        if let peripheral = sampledPeripheral {
            central.cancelPeripheralConnection(peripheral)
            sampledPeripheral = nil
        }

        sampledDeviceID = nil
        selectedRSSI = nil
        updateScanState()
    }

    private func beginSampling() {
        guard let id = sampledDeviceID, central.state == .poweredOn else { return }

        if usePassiveMode {
            updateScanState()
        } else {
            guard let peripheral = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
            peripheral.delegate = self
            sampledPeripheral = peripheral
            central.connect(peripheral, options: nil)
        }
    }

    /// One scan serves both the device list and passive sampling, so it stops only
    /// when neither still needs it.
    private func updateScanState() {
        guard central.state == .poweredOn else { return }

        let wantScan = isDiscovering || (sampledDeviceID != nil && usePassiveMode)

        if wantScan {
            // Duplicate advertisements are what make the readings live; without this
            // a device is reported once and its value freezes.
            central.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
        } else {
            central.stopScan()
        }

        if isDiscovering {
            startRefreshTimer()
        } else {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private func recordSample(rssi: Int, at time: Date) {
        selectedRSSI = rssi
        onSample?(rssi, time)
    }

    private func startRefreshTimer() {
        guard refreshTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.publishDiscovered() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func publishDiscovered() {
        let cutoff = Date().addingTimeInterval(-Self.staleAfter)
        let live = seen.values.filter { $0.lastSeen > cutoff }

        // Sorted by name, deliberately not by signal strength. Signal ordering looks
        // helpful but rewrites the list several times a second as readings drift,
        // so rows move out from under the pointer and the list cannot be clicked.
        // The user identifies their watch by name and by watching its value move.
        let next = live.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        guard next != discovered else { return }
        discovered = next
    }

    private func handleStateChange() {
        switch central.state {
        case .poweredOn:
            unavailability = nil
            updateScanState()
            beginSampling()
        case .poweredOff:
            unavailability = .bluetoothOff
            reset()
        case .unauthorized:
            unavailability = .unauthorised
            reset()
        case .unsupported:
            unavailability = .unsupported
            reset()
        default:
            unavailability = .starting
            reset()
        }
    }

    private func reset() {
        seen.removeAll()
        discovered = []
        selectedRSSI = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        pollTimer?.invalidate()
        pollTimer = nil
        sampledPeripheral = nil
    }
}

extension WatchMonitor: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated { handleStateChange() }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // The advertised local name is often absent for Apple devices; the system
        // supplies `peripheral.name` for devices it already knows.
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let rssi = RSSI.intValue

        let id = peripheral.identifier

        MainActor.assumeIsolated {
            // An RSSI of 127 is CoreBluetooth's "not available" sentinel, not a reading.
            guard rssi != 127 else { return }

            // Passive sampling reads the selected device's signal straight off its
            // advertisements, without ever connecting to it.
            if usePassiveMode, id == sampledDeviceID {
                recordSample(rssi: rssi, at: Date())
            }

            // A device with no name cannot be identified by the user in the list.
            guard let name, !name.isEmpty else { return }
            seen[id] = DiscoveredDevice(id: id, name: name, rssi: rssi, lastSeen: Date())
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            guard peripheral.identifier == sampledDeviceID else { return }
            startPolling(peripheral)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            guard peripheral.identifier == sampledDeviceID else { return }
            pollTimer?.invalidate()
            pollTimer = nil

            // A dropped connection is not itself a reason to lock. It just stops
            // samples arriving, and the engine's no-signal timeout decides. Keeping
            // that judgement in one place stops the two lock paths disagreeing.
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            guard peripheral.identifier == sampledDeviceID else { return }
            central.connect(peripheral, options: nil)
        }
    }
}

extension WatchMonitor: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        let rssi = RSSI.intValue
        MainActor.assumeIsolated {
            guard error == nil, rssi != 127, peripheral.identifier == sampledDeviceID else { return }
            recordSample(rssi: rssi, at: Date())
        }
    }
}

private extension WatchMonitor {

    func startPolling(_ peripheral: CBPeripheral) {
        pollTimer?.invalidate()
        peripheral.readRSSI()

        let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let peripheral = self.sampledPeripheral else { return }
                guard peripheral.state == .connected else { return }
                peripheral.readRSSI()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }
}
