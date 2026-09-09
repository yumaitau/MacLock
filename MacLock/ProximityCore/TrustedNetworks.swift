//
//  TrustedNetworks.swift
//  MacLock
//

import Foundation

/// Whether the Wi-Fi network the Mac is on is one the user marked trusted.
///
/// `ssid` is optional because "which network is this?" is a question macOS often
/// refuses to answer -- Location access not granted, Wi-Fi switched off, or the Mac
/// on Ethernet and associated with nothing. An unanswered question is never a match.
///
/// That is the same rule as the rest of MacLock, pointed the other way. Elsewhere
/// absence of evidence must not make it lock; here absence of evidence must not make
/// it *stop guarding*, which would leave the Mac unwatched everywhere while looking
/// like the feature working.
///
/// The comparison is exact. SSIDs are case-sensitive, and standing down is MacLock
/// giving up its whole job, so it is not a decision to make on an approximate match
/// with a network that merely looks like the right one. Typos are handled at the
/// point of entry by ``normalizedNetworkName(_:)`` and by letting the user add the
/// network they are on rather than type it.
public nonisolated func isOnTrustedNetwork(ssid: String?, trusted: [String]) -> Bool {
    guard let ssid, !ssid.isEmpty else { return false }
    return trusted.contains(ssid)
}

/// Cleans a network name typed by the user, or returns `nil` if nothing is left.
///
/// Trimming happens here, once, rather than at comparison time: a stored name is
/// then exactly the string that must match, and a network whose real name ends in a
/// space is still reachable by adding the network the Mac is on.
public nonisolated func normalizedNetworkName(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

/// The trusted list with `raw` added, or `nil` when the name is blank once trimmed.
///
/// `nil` rather than an unchanged list is what lets a caller tell a refused entry from
/// a duplicate: the text field clears on one and keeps its contents on the other.
/// Adding a network already trusted succeeds and changes nothing -- the user asked for
/// it to be trusted, and it is.
public nonisolated func addingTrustedNetwork(_ raw: String, to trusted: [String]) -> [String]? {
    guard let name = normalizedNetworkName(raw) else { return nil }
    guard !trusted.contains(name) else { return trusted }
    return trusted + [name]
}

/// The trusted list without `name`, matched exactly like every other comparison here,
/// so removing one network cannot quietly drop another that differs only in case.
public nonisolated func removingTrustedNetwork(_ name: String, from trusted: [String]) -> [String] {
    trusted.filter { $0 != name }
}
