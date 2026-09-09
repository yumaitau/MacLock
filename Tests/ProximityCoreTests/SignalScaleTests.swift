import Testing

@testable import ProximityCore

@Suite("SignalScale")
struct SignalScaleTests {

    /// The orientation is the whole point: dBm gets *less* negative as the watch
    /// gets closer, so a meter drawn from the raw number reads backwards.
    @Test("The weak end of the range reads empty and the strong end reads full")
    func endsOfTheRange() {
        #expect(signalFraction(rssi: -100, in: -100...(-40)) == 0)
        #expect(signalFraction(rssi: -40, in: -100...(-40)) == 1)
    }

    @Test("A reading inside the range reads its proportion of the way along")
    func middleOfTheRange() {
        #expect(signalFraction(rssi: -70, in: -100...(-40)) == 0.5)
        #expect(signalFraction(rssi: -85, in: -100...(-40)) == 0.25)
    }

    /// Real radios report outside any range the UI picked, and a fraction below 0 or
    /// above 1 draws a bar past its own track.
    @Test("A reading beyond either end is clamped, not drawn off the meter")
    func readingsOutsideTheRange() {
        #expect(signalFraction(rssi: -120, in: -100...(-40)) == 0)
        #expect(signalFraction(rssi: -20, in: -100...(-40)) == 1)
    }

    /// A hand-edited preferences file can collapse the range to a point, and a
    /// division by zero would put NaN into a view's layout.
    @Test("A range with no width still reports a usable fraction")
    func degenerateRange() {
        #expect(signalFraction(rssi: -75, in: -75...(-75)) == 1)
        #expect(signalFraction(rssi: -80, in: -75...(-75)) == 0)
    }
}
