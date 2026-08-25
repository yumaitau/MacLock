//
//  MonitoringGate.swift
//  MacLock
//

/// Why MacLock is not watching the watch right now.
public nonisolated enum StandDownReason: Sendable, Equatable {
    /// The lock primitive could not be bound, so MacLock cannot lock at all.
    case cannotLock
    /// No watch has been chosen.
    case noDevice
    /// The user paused monitoring.
    case paused
    /// Bluetooth is off, unauthorised or unsupported.
    case cannotMonitor
}

/// Whether MacLock should be sampling the watch at all.
public nonisolated enum MonitoringDecision: Sendable, Equatable {
    case monitor
    case standDown(StandDownReason)
}

/// The observable facts the decision is made from.
public nonisolated struct MonitoringInputs: Sendable, Equatable {
    public var canLock: Bool
    public var hasDevice: Bool
    public var isPaused: Bool
    public var bluetoothAvailable: Bool

    public init(canLock: Bool, hasDevice: Bool, isPaused: Bool, bluetoothAvailable: Bool) {
        self.canLock = canLock
        self.hasDevice = hasDevice
        self.isPaused = isPaused
        self.bluetoothAvailable = bluetoothAvailable
    }
}

/// Decides whether MacLock may watch the user's watch.
///
/// This is the rule behind "absence of evidence is never evidence of absence": in
/// every stand-down state MacLock has no information about where the user is, so it
/// must not sample and must not lock. It is a pure function so the safety-critical
/// branching can be tested without Bluetooth, a screen or a clock.
///
/// The order matters: it is also the precedence the menu bar icon uses, so the most
/// fundamental problem is the one reported.
public nonisolated func monitoringDecision(_ inputs: MonitoringInputs) -> MonitoringDecision {
    if !inputs.canLock { return .standDown(.cannotLock) }
    if !inputs.hasDevice { return .standDown(.noDevice) }
    if inputs.isPaused { return .standDown(.paused) }
    if !inputs.bluetoothAvailable { return .standDown(.cannotMonitor) }
    return .monitor
}
