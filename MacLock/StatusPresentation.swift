//
//  StatusPresentation.swift
//  MacLock
//

import SwiftUI

/// How ``MacLockController/Status`` is drawn.
///
/// It lives apart from the controller so the controller keeps knowing nothing about
/// SwiftUI, and apart from any one panel because the menu bar dropdown and the Watch
/// settings panel show the same state and must never disagree about it.
extension MacLockController.Status {

    /// The state as a glyph. Every case gets its own, so the shape carries the
    /// meaning before the words are read.
    var symbolName: String {
        switch self {
        case .cannotLock: "exclamationmark.triangle.fill"
        case .cannotMonitor: "antenna.radiowaves.left.and.right.slash"
        case .noDevice: "applewatch.slash"
        case .paused: "pause.circle.fill"
        case .onTrustedNetwork: "wifi.circle.fill"
        case .locked: "lock.fill"
        case .away: "figure.walk.departure"
        case .inRange: "checkmark.shield.fill"
        case .waitingForSignal: "dot.radiowaves.left.and.right"
        }
    }

    /// Red means MacLock cannot do its job, orange means it is not doing it right
    /// now, green means it is. Nothing here is decorative.
    var tint: Color {
        switch self {
        case .cannotLock, .cannotMonitor: .red
        case .noDevice: .orange
        case .paused, .locked, .waitingForSignal: .secondary
        case .onTrustedNetwork: .blue
        case .away: .orange
        case .inRange: .green
        }
    }

    /// The state in one short sentence.
    ///
    /// Deliberately not ``label``: that one has to stand alone as the menu bar icon's
    /// accessibility text, so it repeats whether MacLock is watching. Here a header
    /// line has already said that, and repeating it reads as noise.
    var summary: String {
        switch self {
        case .cannotLock(let reason):
            reason.isEmpty ? "This Mac cannot be locked." : reason
        case .cannotMonitor(let reason):
            reason.isEmpty ? "Your watch cannot be watched right now." : reason
        case .noDevice:
            "Choose your watch to start."
        case .paused:
            "Monitoring is paused."
        case .onTrustedNetwork(let name):
            name.isEmpty ? "On a trusted network." : "On \"\(name)\", a trusted network."
        case .locked:
            "The screen is locked."
        case .away:
            "Your watch is out of range."
        case .inRange:
            "Your watch is nearby."
        case .waitingForSignal:
            "Looking for your watch."
        }
    }
}
