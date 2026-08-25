//
//  ScreenLocker.swift
//  MacLock
//

import AppKit
import Foundation

/// Locks the screen, and reports whether the screen is actually locked.
///
/// The lock primitive is `SACLockScreenImmediate` from the private login framework -
/// the same call the system's own Lock Screen menu item makes. The framework on disk
/// is a stub and the symbol lives in the dyld shared cache, so it is bound at runtime
/// rather than linked.
///
/// The function returns `void`, so calling it proves nothing. Success is observed
/// instead, from the system's screen-lock notifications.
@Observable
@MainActor
final class ScreenLocker {

    enum Availability: Equatable {
        case available
        /// MacLock cannot lock at all. It must say so and refuse to arm rather than
        /// sit in the menu bar pretending to guard the Mac.
        case unavailable(String)
    }

    private static let frameworkPath = "/System/Library/PrivateFrameworks/login.framework/login"
    private static let symbolName = "SACLockScreenImmediate"

    /// Whether the lock primitive could be bound. Resolved once, at startup.
    let availability: Availability

    /// Whether the screen is locked right now, as reported by the system.
    private(set) var screenIsLocked: Bool

    /// Holds the notification observers and unregisters them when the locker goes
    /// away. It lives in its own non-isolated box because `deinit` cannot touch
    /// main-actor state.
    private final class ObserverTokens: @unchecked Sendable {
        var tokens: [any NSObjectProtocol] = []

        deinit {
            let center = DistributedNotificationCenter.default()
            for token in tokens {
                center.removeObserver(token)
            }
        }
    }

    private let lockFunction: (@convention(c) () -> Void)?
    private let observers = ObserverTokens()

    init() {
        var resolved: (@convention(c) () -> Void)?
        var failure: String?

        if let handle = dlopen(Self.frameworkPath, RTLD_NOW) {
            if let symbol = dlsym(handle, Self.symbolName) {
                resolved = unsafeBitCast(symbol, to: (@convention(c) () -> Void).self)
            } else {
                let detail = dlerror().map { String(cString: $0) } ?? "symbol not found"
                failure = "Could not find \(Self.symbolName) in the login framework: \(detail)"
            }
        } else {
            let detail = dlerror().map { String(cString: $0) } ?? "unknown error"
            failure = "Could not open the login framework: \(detail)"
        }

        self.lockFunction = resolved
        self.availability = failure.map(Availability.unavailable) ?? .available
        self.screenIsLocked = Self.readCurrentLockState()

        startObserving()
    }

    /// Requests an immediate, password-protected lock.
    ///
    /// Returns nothing, because the primitive reports nothing. Observe
    /// ``screenIsLocked`` to find out whether it took effect.
    func lock() {
        guard let lockFunction else { return }
        lockFunction()
    }

    private func startObserving() {
        let center = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            let token = center.addObserver(
                forName: Notification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.screenIsLocked = locked }
            }
            observers.tokens.append(token)
        }
    }

    /// The session dictionary carries `CGSSessionScreenIsLocked` only while locked,
    /// so an absent key means unlocked.
    private static func readCurrentLockState() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
