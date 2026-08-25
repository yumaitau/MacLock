//
//  ProximityEngine.swift
//  MacLock
//

import Foundation

/// Why the engine decided the Mac should be locked.
public nonisolated enum LockReason: Sendable, Equatable {
    /// The smoothed signal stayed below the threshold for the whole away delay.
    case away
    /// No sample arrived for the whole no-signal timeout.
    case signalLost
}

/// What the engine currently believes about the watch.
public nonisolated enum ProximityState: Sendable, Equatable {
    /// No sample observed yet, so nothing is known.
    case unknown
    /// The smoothed signal is at or above the threshold.
    case inRange
    /// The smoothed signal is below the threshold; the away delay may still be running.
    case away
    /// Nothing has been heard for longer than the no-signal timeout.
    case signalLost
}

/// User-tunable thresholds. Defaults are starting points the user calibrates
/// against the live readout; they are not meant to be right for every room.
public nonisolated struct ProximityConfiguration: Sendable, Equatable {
    /// Smoothed RSSI at or above which the watch counts as in range, in dBm.
    public var lockThreshold: Int
    /// How long the smoothed signal must stay below the threshold before locking.
    public var awayDelay: TimeInterval
    /// How long silence must last before locking.
    public var noSignalTimeout: TimeInterval
    /// Number of recent samples averaged together.
    public var smoothingWindow: Int

    public init(
        lockThreshold: Int = -75,
        awayDelay: TimeInterval = 5,
        noSignalTimeout: TimeInterval = 30,
        smoothingWindow: Int = 5
    ) {
        self.lockThreshold = lockThreshold
        self.awayDelay = awayDelay
        self.noSignalTimeout = noSignalTimeout
        self.smoothingWindow = smoothingWindow
    }
}

/// Turns a stream of timestamped RSSI samples into lock decisions.
///
/// The engine never reads the clock: callers supply the time with every sample and
/// tick. That is what makes the away delay and the no-signal timeout testable.
public nonisolated struct ProximityEngine {
    /// Changing the smoothing window rebuilds the filter, so a settings change
    /// actually takes effect instead of leaving the old window in place.
    public var configuration: ProximityConfiguration {
        didSet {
            if configuration.smoothingWindow != oldValue.smoothingWindow {
                smoother = RSSISmoother(window: configuration.smoothingWindow)
            }
        }
    }

    /// Whether the screen is currently locked, as observed from the system.
    ///
    /// Repeat locks are suppressed by this input rather than by remembering that a
    /// decision was emitted: a lock that never took effect must not consume the
    /// engine's decision and leave the Mac unlocked and the engine silent.
    public var screenIsLocked: Bool = false

    public private(set) var state: ProximityState = .unknown

    private var smoother: RSSISmoother
    private var belowThresholdSince: Date?
    private var lastSampleAt: Date?

    public init(configuration: ProximityConfiguration = ProximityConfiguration()) {
        self.configuration = configuration
        self.smoother = RSSISmoother(window: configuration.smoothingWindow)
    }

    /// Smoothed signal in dBm, or `nil` before any sample has been recorded.
    public var smoothedRSSI: Int? { smoother.average }

    /// Records a sample and returns a lock decision if one is now due.
    public mutating func record(rssi: Int, at time: Date) -> LockReason? {
        smoother.add(rssi)
        lastSampleAt = time

        if let smoothed = smoother.average, smoothed < configuration.lockThreshold {
            if belowThresholdSince == nil { belowThresholdSince = time }
            state = .away
        } else {
            belowThresholdSince = nil
            state = .inRange
        }

        return decision(at: time)
    }

    /// Advances the clock without a new sample and returns a lock decision if one is
    /// now due. This is what lets the no-signal timeout fire when nothing arrives.
    public mutating func tick(at time: Date) -> LockReason? {
        if let last = lastSampleAt, time.timeIntervalSince(last) >= configuration.noSignalTimeout {
            state = .signalLost
        }
        return decision(at: time)
    }

    /// Clears all history so the next sample starts a fresh away delay.
    ///
    /// Called whenever monitoring starts or restarts - launch, resume from pause,
    /// Bluetooth returning, a device change, or waking from sleep - so a stale
    /// sample history can never fire an immediate lock.
    public mutating func reset() {
        smoother.reset()
        belowThresholdSince = nil
        lastSampleAt = nil
        state = .unknown
    }

    private func decision(at time: Date) -> LockReason? {
        guard !screenIsLocked else { return nil }

        if let last = lastSampleAt, time.timeIntervalSince(last) >= configuration.noSignalTimeout {
            return .signalLost
        }
        if let since = belowThresholdSince, time.timeIntervalSince(since) >= configuration.awayDelay {
            return .away
        }
        return nil
    }
}
