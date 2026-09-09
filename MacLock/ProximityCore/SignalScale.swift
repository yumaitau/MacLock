//
//  SignalScale.swift
//  MacLock
//

/// Where a signal reading sits along a dBm range, as a fraction from 0 to 1.
///
/// This exists so a meter can be *drawn*. RSSI is a small negative number that gets
/// less negative as the watch gets closer, which is exactly the wrong shape for a
/// bar: drawn from the raw value a stronger signal would fill less of the track. The
/// conversion is one expression, but it is the one place the orientation, the
/// clamping and the zero-width range are decided, and each of those has a wrong
/// answer that renders as a plausible-looking bar rather than as an error.
///
/// - Parameters:
///   - rssi: The reading, in dBm. Readings outside `range` are clamped -- a real
///     radio reports well outside whatever range the UI chose to display.
///   - range: The weakest and strongest dBm the meter draws between.
/// - Returns: 0 at the weak end, 1 at the strong end.
public nonisolated func signalFraction(rssi: Int, in range: ClosedRange<Int>) -> Double {
    let width = range.upperBound - range.lowerBound
    // A collapsed range has no interior to place a reading in, so the only
    // meaningful answers are "at or past it" and "short of it".
    guard width > 0 else { return rssi >= range.lowerBound ? 1 : 0 }

    let clamped = min(max(rssi, range.lowerBound), range.upperBound)
    return Double(clamped - range.lowerBound) / Double(width)
}
