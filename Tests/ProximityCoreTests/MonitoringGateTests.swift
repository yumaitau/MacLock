import Testing

@testable import ProximityCore

/// All five observable facts favourable: the only state in which MacLock may watch.
private func ready(
    canLock: Bool = true,
    hasDevice: Bool = true,
    isPaused: Bool = false,
    onTrustedNetwork: Bool = false,
    bluetoothAvailable: Bool = true
) -> MonitoringInputs {
    MonitoringInputs(
        canLock: canLock,
        hasDevice: hasDevice,
        isPaused: isPaused,
        onTrustedNetwork: onTrustedNetwork,
        bluetoothAvailable: bluetoothAvailable
    )
}

@Suite("MonitoringGate")
struct MonitoringGateTests {

    @Test("Monitors only when it can lock, has a device, is unpaused, is off a trusted network and Bluetooth is up")
    func monitorsWhenEverythingIsReady() {
        #expect(monitoringDecision(ready()) == .monitor)
    }

    @Test("Stands down when the lock primitive is unavailable")
    func standsDownWhenItCannotLock() {
        #expect(monitoringDecision(ready(canLock: false)) == .standDown(.cannotLock))
    }

    @Test("Stands down when no watch has been chosen")
    func standsDownWithoutADevice() {
        #expect(monitoringDecision(ready(hasDevice: false)) == .standDown(.noDevice))
    }

    @Test("Stands down while the user has paused monitoring")
    func standsDownWhenPaused() {
        #expect(monitoringDecision(ready(isPaused: true)) == .standDown(.paused))
    }

    @Test("Stands down when Bluetooth cannot be used")
    func standsDownWithoutBluetooth() {
        #expect(monitoringDecision(ready(bluetoothAvailable: false)) == .standDown(.cannotMonitor))
    }

    @Test("Stands down while the Mac is on a network the user marked trusted")
    func standsDownOnATrustedNetwork() {
        #expect(monitoringDecision(ready(onTrustedNetwork: true)) == .standDown(.trustedNetwork))
    }

    /// The property that matters: every state other than fully-ready stands down.
    /// This is "absence of evidence is never evidence of absence" stated exhaustively,
    /// so a future sixth input cannot quietly default to monitoring.
    @Test("Any missing precondition stands down, in every combination")
    func anyMissingPreconditionStandsDown() {
        for canLock in [true, false] {
            for hasDevice in [true, false] {
                for isPaused in [true, false] {
                    for onTrustedNetwork in [true, false] {
                        for bluetooth in [true, false] {
                            let inputs = ready(
                                canLock: canLock,
                                hasDevice: hasDevice,
                                isPaused: isPaused,
                                onTrustedNetwork: onTrustedNetwork,
                                bluetoothAvailable: bluetooth
                            )
                            let allReady = canLock && hasDevice && !isPaused
                                && !onTrustedNetwork && bluetooth
                            if allReady {
                                #expect(monitoringDecision(inputs) == .monitor)
                            } else {
                                #expect(monitoringDecision(inputs) != .monitor)
                            }
                        }
                    }
                }
            }
        }
    }

    @Test("Reports the most fundamental problem when several apply at once")
    func reportsMostFundamentalProblemFirst() {
        // Cannot lock outranks everything: an app that cannot lock must say so
        // rather than blaming a paused toggle the user can 'fix' to no effect.
        let everythingWrong = ready(
            canLock: false,
            hasDevice: false,
            isPaused: true,
            onTrustedNetwork: true,
            bluetoothAvailable: false
        )
        #expect(monitoringDecision(everythingWrong) == .standDown(.cannotLock))

        #expect(monitoringDecision(ready(hasDevice: false, isPaused: true)) == .standDown(.noDevice))
        #expect(monitoringDecision(ready(isPaused: true, bluetoothAvailable: false)) == .standDown(.paused))
    }

    /// A trusted network is a reason MacLock has chosen not to watch, so it outranks
    /// Bluetooth being unusable: an error icon for a radio the user does not need
    /// right now is noise. It never outranks the three above it -- a Mac that cannot
    /// lock, has no watch chosen, or was paused by hand must say so, because those
    /// are the states the user can actually do something about.
    @Test("A trusted network outranks a Bluetooth problem, and nothing above it")
    func trustedNetworkSitsBetweenPausedAndBluetooth() {
        #expect(
            monitoringDecision(ready(onTrustedNetwork: true, bluetoothAvailable: false))
                == .standDown(.trustedNetwork)
        )

        #expect(monitoringDecision(ready(canLock: false, onTrustedNetwork: true)) == .standDown(.cannotLock))
        #expect(monitoringDecision(ready(hasDevice: false, onTrustedNetwork: true)) == .standDown(.noDevice))
        #expect(monitoringDecision(ready(isPaused: true, onTrustedNetwork: true)) == .standDown(.paused))
    }
}
