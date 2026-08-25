import Foundation
import Testing

@testable import ProximityCore

/// Fixed clock origin. Every test drives time explicitly so the away delay and the
/// no-signal timeout are exercised without waiting on a real clock.
private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func config(
    lockThreshold: Int = -75,
    awayDelay: TimeInterval = 5,
    noSignalTimeout: TimeInterval = 30,
    smoothingWindow: Int = 5
) -> ProximityConfiguration {
    ProximityConfiguration(
        lockThreshold: lockThreshold,
        awayDelay: awayDelay,
        noSignalTimeout: noSignalTimeout,
        smoothingWindow: smoothingWindow
    )
}

/// Fills the smoothing window so later assertions are not diluted by an empty filter.
private func settle(_ engine: inout ProximityEngine, rssi: Int, from start: Date, count: Int = 5) {
    for i in 0..<count {
        _ = engine.record(rssi: rssi, at: start.addingTimeInterval(Double(i)))
    }
}

@Suite("ProximityEngine")
struct ProximityEngineTests {

    @Test("No lock before the away delay elapses, and one once it does")
    func awayLockWaitsForTheDelay() {
        var engine = ProximityEngine(configuration: config(awayDelay: 5, smoothingWindow: 1))
        settle(&engine, rssi: -60, from: t0, count: 1)

        // Signal drops at t0+10; the delay must not be satisfied by the drop alone.
        #expect(engine.record(rssi: -90, at: t0.addingTimeInterval(10)) == nil)
        #expect(engine.record(rssi: -90, at: t0.addingTimeInterval(14)) == nil)
        #expect(engine.state == .away)

        #expect(engine.record(rssi: -90, at: t0.addingTimeInterval(15)) == .away)
    }

    @Test("A dip that recovers before the delay never locks")
    func recoveredDipDoesNotLock() {
        var engine = ProximityEngine(configuration: config(awayDelay: 5, smoothingWindow: 1))
        settle(&engine, rssi: -60, from: t0, count: 1)

        #expect(engine.record(rssi: -90, at: t0.addingTimeInterval(10)) == nil)
        #expect(engine.record(rssi: -60, at: t0.addingTimeInterval(13)) == nil)
        #expect(engine.state == .inRange)

        // Well past the original delay window, but the timer restarted on recovery.
        #expect(engine.record(rssi: -60, at: t0.addingTimeInterval(20)) == nil)
    }

    @Test("Silence past the no-signal timeout locks, and reports a different reason")
    func silenceLocksWithSignalLost() {
        var engine = ProximityEngine(configuration: config(awayDelay: 5, noSignalTimeout: 30))
        settle(&engine, rssi: -60, from: t0)
        let lastSample = t0.addingTimeInterval(4)

        #expect(engine.tick(at: lastSample.addingTimeInterval(29)) == nil)

        let reason = engine.tick(at: lastSample.addingTimeInterval(30))
        #expect(reason == .signalLost)
        #expect(reason != .away)
        #expect(engine.state == .signalLost)
    }

    @Test("A locked screen suppresses decisions; unlocking while still away resumes them")
    func lockedScreenSuppressesDecisions() {
        var engine = ProximityEngine(configuration: config(awayDelay: 5, smoothingWindow: 1))
        settle(&engine, rssi: -60, from: t0, count: 1)
        _ = engine.record(rssi: -90, at: t0.addingTimeInterval(10))

        #expect(engine.record(rssi: -90, at: t0.addingTimeInterval(15)) == .away)

        engine.screenIsLocked = true
        #expect(engine.record(rssi: -90, at: t0.addingTimeInterval(16)) == nil)
        #expect(engine.record(rssi: -90, at: t0.addingTimeInterval(60)) == nil)

        // The screen came back up while the watch is still away: guard again.
        engine.screenIsLocked = false
        #expect(engine.record(rssi: -90, at: t0.addingTimeInterval(61)) == .away)
    }

    @Test("A lock that never took effect does not silence the engine")
    func unconfirmedLockKeepsDeciding() {
        var engine = ProximityEngine(configuration: config(awayDelay: 5, smoothingWindow: 1))
        settle(&engine, rssi: -60, from: t0, count: 1)
        _ = engine.record(rssi: -90, at: t0.addingTimeInterval(10))

        #expect(engine.record(rssi: -90, at: t0.addingTimeInterval(15)) == .away)

        // screenIsLocked stays false: the lock did not happen, so the Mac is still
        // exposed and the engine must keep asking for it.
        #expect(engine.record(rssi: -90, at: t0.addingTimeInterval(16)) == .away)
    }

    @Test("Reset clears history so the away delay starts again")
    func resetRestartsTheDelay() {
        var engine = ProximityEngine(configuration: config(awayDelay: 5, smoothingWindow: 1))
        settle(&engine, rssi: -60, from: t0, count: 1)
        _ = engine.record(rssi: -90, at: t0.addingTimeInterval(10))

        engine.reset()
        #expect(engine.state == .unknown)
        #expect(engine.smoothedRSSI == nil)

        // Without the reset this sample would be 6s into the dwell and would lock.
        #expect(engine.record(rssi: -90, at: t0.addingTimeInterval(16)) == nil)
        #expect(engine.record(rssi: -90, at: t0.addingTimeInterval(21)) == .away)
    }

    @Test("Reset also disarms the no-signal timeout until a fresh sample arrives")
    func resetDisarmsSignalLost() {
        var engine = ProximityEngine(configuration: config(noSignalTimeout: 30))
        settle(&engine, rssi: -60, from: t0)

        engine.reset()

        // A wake from sleep long after the last sample must not lock instantly.
        #expect(engine.tick(at: t0.addingTimeInterval(10_000)) == nil)
    }

    @Test("One outlier sample does not drag the smoothed value across the threshold")
    func singleOutlierIsSmoothedAway() {
        var engine = ProximityEngine(configuration: config(lockThreshold: -75, smoothingWindow: 5))
        settle(&engine, rssi: -60, from: t0, count: 4)

        // Raw -100 is far below the threshold; averaged with four -60s it is -68.
        #expect(engine.record(rssi: -100, at: t0.addingTimeInterval(4)) == nil)
        #expect(engine.smoothedRSSI == -68)
        #expect(engine.state == .inRange)
    }

    @Test("Narrowing the smoothing window takes effect on later samples")
    func changingSmoothingWindowRebuildsTheFilter() {
        var engine = ProximityEngine(configuration: config(lockThreshold: -75, smoothingWindow: 5))
        settle(&engine, rssi: -60, from: t0, count: 5)
        #expect(engine.smoothedRSSI == -60)

        engine.configuration.smoothingWindow = 1

        // With a window of 1 the outlier is the whole average, so it crosses.
        #expect(engine.record(rssi: -100, at: t0.addingTimeInterval(5)) == nil)
        #expect(engine.smoothedRSSI == -100)
        #expect(engine.state == .away)
    }
}
