//
//  RSSISmoother.swift
//  MacLock
//

/// Moving average over the most recent RSSI readings.
///
/// Raw RSSI from a stationary device swings by 10-20 dBm from multipath and body
/// shadowing, so no proximity judgement is ever made on a single sample.
nonisolated struct RSSISmoother {
    private var samples: [Int] = []
    private let window: Int

    init(window: Int) {
        self.window = max(1, window)
    }

    mutating func add(_ rssi: Int) {
        samples.append(rssi)
        if samples.count > window {
            samples.removeFirst(samples.count - window)
        }
    }

    /// Mean of the retained samples, rounded to the nearest dBm; `nil` before any sample.
    var average: Int? {
        guard !samples.isEmpty else { return nil }
        let total = samples.reduce(0, +)
        return Int((Double(total) / Double(samples.count)).rounded())
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }
}
