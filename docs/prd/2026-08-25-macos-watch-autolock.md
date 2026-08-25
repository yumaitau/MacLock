# MacLock — Apple Watch Proximity Auto-Lock

Created: 2026-08-25
Author: josh@luongo.com.au
Agent: Claude Code
Category: Feature
Status: Final
Research: Standard

## Problem Statement

Walking away from an unlocked Mac leaves it exposed — in an office, a co-working space, or anywhere someone else can reach the keyboard. macOS solves the *return* half natively ("Unlock with Apple Watch") but has no built-in walk-away lock. MacLock closes that gap: a menu bar utility that monitors the Bluetooth signal of the user's selected Apple Watch and locks the Mac automatically when the watch — and therefore the user — moves out of range.

## Core User Flows

### Flow 1: First-run setup

1. User launches MacLock; an icon appears in the menu bar (no Dock icon, no main window).
2. macOS prompts for Bluetooth permission; the user grants it.
3. User opens the settings surface from the menu bar icon and starts a device scan.
4. MacLock lists nearby Apple devices with name and live signal strength; the user identifies their watch (confirming it by watching the signal change as they move it) and selects it.
5. User sets the lock threshold on a distance slider that shows the watch's live smoothed signal against the chosen cut-off, so "how far is far enough" is set by feel, not by guessing numbers.
6. MacLock is now armed. The selection and settings persist across relaunches.

### Flow 2: Walk-away lock

1. User walks away from the Mac wearing the selected watch.
2. The watch's smoothed signal falls below the lock threshold and stays there for the configured dwell time (grace period against momentary dips).
3. MacLock locks the Mac immediately — a real password-protected lock, straight to the lock screen.
4. The menu bar icon reflects the state throughout: in range / away / locked.
5. User returns; macOS's native "Unlock with Apple Watch" (or Touch ID / password) unlocks the Mac. MacLock resumes monitoring without any user action.

### Flow 3: Signal lost

1. The watch stops being heard entirely (out of radio range, powered off, Bluetooth interference) — no signal to compare against a threshold.
2. After a separate no-signal timeout elapses, MacLock locks the Mac.

### Flow 4: Pause and resume

1. User is staying at their desk but the watch is elsewhere (charging in another room, on aeroplane mode).
2. User toggles "Pause" from the menu bar; MacLock stops monitoring and will not lock. The icon shows the disarmed state.
3. User toggles it back when done; monitoring resumes with the saved device and settings.

## Scope

### In Scope

- Menu bar app with a status icon showing four states: in range, away/locking, locked, paused.
- Device scan and selection: list nearby Apple devices with live signal strength; user selects their watch; selection persists across launches and reboots.
- Lock trigger: smoothed RSSI threshold (user-set via live-feedback slider) + configurable dwell time before locking + separate configurable no-signal timeout.
- Immediate, real screen lock (password required to re-enter) when triggered.
- Pause/resume monitoring toggle.
- Launch at login option.
- Settings persistence.

### Explicitly Out of Scope

- **Auto-unlock on return** — macOS's native "Unlock with Apple Watch" already covers it; replicating it requires storing the login password and simulating typing at the login screen, a large security surface for no gain.
- **Generic BLE / iPhone device support** — the product is watch-focused; BLEUnlock already exists for arbitrary BLE devices, and generic support drags in the rotating-MAC-address problem for non-Apple hardware.
- **Companion iOS/watchOS app** — not needed; the watch is observed passively over BLE, nothing runs on it.
- **Script hooks, media pause, wake-on-proximity** — BLEUnlock power features, not the core walk-away-lock job.
- **Multi-device or multi-Mac coordination** — one watch, one Mac per instance.
- **Mac App Store distribution** — the chosen lock mechanism uses a private API (see Key Decisions); the app is notarised and distributed directly.

## Technical Context

- **Existing code:** fresh Xcode SwiftUI template — `MacLock/MacLockApp.swift` (WindowGroup scene) and `MacLock/ContentView.swift` (placeholder view). Bundle id `au.com.yumait.MacLock`, deployment target macOS 26.5, Swift 5, automatic signing. No behaviour exists yet.
- **Constraints:**
  - macOS has no public "distance to device" API. The only viable signal is Core Bluetooth RSSI, which is noisy (readings at a fixed 3 m can swing ~20 dBm) — hence smoothing, threshold, and dwell rather than metres.
  - Apple Watches rotate their private BLE MAC address (~every 15 min). macOS resolves the watch to its true static address **only when the watch is signed into the same Apple ID as the Mac** — stable watch selection depends on this, and the app targets that configuration.
  - The real lock primitive is `SACLockScreenImmediate` in the private `login.framework` — it exists on current macOS and is what comparable utilities use, but it is a private API, which forecloses Mac App Store distribution.
  - The project template currently has App Sandbox enabled; the sandbox is incompatible with the private-API lock approach chosen for this app.
  - Core Bluetooth access requires an `NSBluetoothAlwaysUsageDescription` purpose string and a user consent prompt on first scan.
- **Relevant architecture / prior art:** [BLEUnlock](https://github.com/ts1/BLEUnlock) (MIT licence) implements the same monitoring problem and documents the field-proven parameter set: moving-average RSSI smoothing, delay-to-lock, no-signal timeout, and a passive (advertisement-observing) vs active (connect-and-poll) monitoring distinction — active polling can interfere with other Bluetooth peripherals.

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Lock vs lock + unlock | Lock only | Native "Unlock with Apple Watch" covers the return path; auto-unlock would require storing the login password and synthesising keyboard input — large security surface, no added value. |
| App shape | Menu bar utility, no Dock icon | Standard shape for an always-running background tool; the app has no document or main-window content. |
| Distribution / lock mechanism | Direct distribution (notarised), private `SACLockScreenImmediate` lock, sandbox off | A guaranteed instant password-protected lock is the product's whole promise; the App Store-legal alternative (screensaver + "require password immediately" setting) is weaker and silently breaks if the user's setting is off. Personal/YumaIT tool — store distribution not needed. |
| "Distance" model | Smoothed RSSI threshold + dwell time + no-signal timeout, set via live-feedback slider | RSSI does not map to metres; a fake metres setting would miscalibrate per environment. Live feedback lets the user set the threshold empirically. Dwell prevents momentary-dip false locks; no-signal timeout handles disappearance as a distinct case. |
| Device support | Apple Watch (Apple devices, same Apple ID) only | The same-Apple-ID static-address resolution makes selection reliable; generic BLE reintroduces the rotating-MAC problem and is already served by BLEUnlock. |
| Research tier | Standard | BLE proximity locking is well-trodden; in-session research confirmed the approach and surfaced the proven parameter set. |

## Research Findings

- **Prior art:** [BLEUnlock](https://github.com/ts1/BLEUnlock) (MIT, menu bar, Core Bluetooth) is the closest open-source implementation and validates every mechanism this PRD relies on. Commercial peers — Near Lock, Unlox, ProximityLock, "Unlock – Modern Proximity Lock" — confirm the product category.
- **Watch identity:** BLE privacy rotates MAC addresses, but Apple devices signed into the same Apple ID as the Mac resolve to their true static address (BLEUnlock README, "Notes on MAC address"). Non-Apple devices cannot be tracked reliably — one reason to keep scope watch-only.
- **Locking:** `SACLockScreenImmediate` (private `login.framework`) is the direct lock used by BLEUnlock and documented by [Timac's analysis](https://blog.timac.org/2016/0605-programmatically-lock-the-screen/). App Store-safe alternatives (screensaver, display sleep) depend on the "require password immediately" system setting.
- **RSSI behaviour:** raw RSSI is noisy (±10 dBm swings at fixed distance from multipath and body shadowing); moving-average smoothing plus threshold-with-dwell is the standard practical recipe. Kalman filtering exists as a refinement but is not required for this use case.
- **Permissions:** Core Bluetooth requires the `NSBluetoothAlwaysUsageDescription` purpose string; first scan triggers a system consent prompt.
