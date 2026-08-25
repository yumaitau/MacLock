# MacLock Watch Proximity Auto-Lock Implementation Plan

Created: 2026-08-25
Author: josh@luongo.com.au
Agent: Claude Code
Status: VERIFIED
Approved: Yes
Iterations: 0
Worktree: No
Type: Feature

## Summary

**Goal:** A menu bar app that watches the Bluetooth signal of a chosen Apple Watch and locks the Mac when the watch moves out of range, with the threshold calibrated by the user against a live signal readout.

Requirements come from `docs/prd/2026-08-25-macos-watch-autolock.md`.

## Out of Scope

- **Auto-unlock on return** — macOS's native "Unlock with Apple Watch" covers it; replicating it would mean storing the login password and synthesising keystrokes at the login window.
- **Generic BLE / iPhone device support** — selection is restricted to Apple devices resolvable by the same-Apple-ID mechanism, which is what keeps the identifier stable.
- **Notarisation, packaging, and distribution** — the app is built and run locally; shipping it is separate work.
- **Copying BLEUnlock source** — it is referenced for approach only. All code here is written fresh; no MIT-licensed source is transplanted.
- **Localisation** — user-facing copy is Australian English only.

## Approach

**Chosen:** Greenfield build inside the existing `MacLock` target, replacing `ContentView` and the `WindowGroup` scene in `MacLock/MacLockApp.swift:11` with `MenuBarExtra` + `Settings` scenes.

**Why:** The repository is a bare SwiftUI template — both existing files are placeholders, so there is nothing to extend and no pattern to follow. The target uses `PBXFileSystemSynchronizedRootGroup`, so every new `.swift` file under `MacLock/` joins the build with no project-file edits; the only pbxproj changes needed are build-setting values. Pure proximity logic is isolated in `MacLock/ProximityCore/` and exposed to a root `Package.swift` via an explicit target `path:`, so `swift test` exercises it in about a second while the app compiles the same files through the synchronized group — no local package reference, no new target, no structural pbxproj surgery. The cost is that `ProximityCore` cannot take third-party dependencies of its own without being converted to a real package (see Risks).

## Global Constraints

- Deployment target `MACOSX_DEPLOYMENT_TARGET = 26.5`; `SWIFT_VERSION = 5.0` (Swift 5 language mode under the Swift 6.3.3 compiler); `SWIFT_APPROACHABLE_CONCURRENCY = YES` and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` are already on, and `ENABLE_HARDENED_RUNTIME = YES`.
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` applies to the app target but not to the SwiftPM package**, so files under `MacLock/ProximityCore/` would be `@MainActor` in one compilation and non-isolated in the other. Every type there must therefore be annotated `nonisolated` explicitly, pinning its isolation in both builds independent of any build setting. (Discovered while implementing Task 1; the hardened runtime is not a problem for the `dlopen` in Task 3 because the private framework is Apple-signed and library validation permits it.)
- Bundle identifier `au.com.yumait.MacLock`; `DEVELOPMENT_TEAM = 2L7828W29X`; `CODE_SIGN_STYLE = Automatic`.
- `ENABLE_APP_SANDBOX` must be `NO` in **both** the Debug and Release configurations (currently `YES` at `MacLock.xcodeproj/project.pbxproj:257` and `:289`).
- `GENERATE_INFOPLIST_FILE = YES` — every Info.plist key is set as an `INFOPLIST_KEY_<key>` build setting in both configurations, never by adding an Info.plist file.
- Screen lock primitive: `dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_NOW)` then `dlsym(handle, "SACLockScreenImmediate")`, cast to `@convention(c) () -> Void`. The on-disk framework is a stub and the symbol lives in the dyld shared cache, so it must be bound at runtime — it cannot be linked or forward-declared. **The function returns `void`** ([Timac's disassembly](https://blog.timac.org/2016/0605-programmatically-lock-the-screen/) declares `extern void SACLockScreenImmediate();`), so casting it to an `Int32`-returning type and testing the result reads an undefined register. Some published samples do exactly that; do not copy them. Success is never inferred from a return value.
- Observed screen-lock state comes from `DistributedNotificationCenter.default()` observing `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked`. This is the only trustworthy signal that a lock took effect, and it is the same signal that drives the locked menu bar icon state.
- Build: `xcodebuild -project MacLock.xcodeproj -scheme MacLock -configuration Debug build`
- Tests: `swift test`
- User-facing copy is Australian English (`~/.claude/skills/australian-english`). Swift identifiers and Apple API names keep their original spelling.
- No SF Symbol name may be used until it has been confirmed to render — a wrong name fails silently as a blank image.

## Context for Implementer

Bluetooth RSSI is not distance. Readings from a stationary device routinely swing 10–20 dBm from multipath and body shadowing, so every proximity judgement in this app is made on a *smoothed* value held below a threshold for a *sustained* period — never on a single sample. This is why the user calibrates against a live readout rather than typing a distance in metres, and why two independent timers exist: one for "signal is weak" and a separate, longer one for "signal is absent entirely". The two are different events with different causes, and collapsing them into one produces both false locks and missed locks.

The second theme is that MacLock must distinguish *the user is away* from *MacLock cannot tell*. Bluetooth switched off, no device selected, and monitoring paused are all states where the app has no evidence about the user's location. Locking in those states would be a false positive triggered by the app's own blindness.

## File Structure

- `Package.swift` (create) — root SwiftPM manifest; declares `ProximityCore` with an explicit `path:` into `MacLock/ProximityCore` and its test target. Not referenced by the Xcode project.
- `MacLock/ProximityCore/ProximityEngine.swift` (create) — public, pure decision engine: consumes timestamped RSSI samples and clock ticks, emits lock decisions. No CoreBluetooth, no AppKit, no I/O.
- `MacLock/ProximityCore/RSSISmoother.swift` (create) — internal moving-average filter over recent samples.
- `MacLock/ProximityCore/MonitoringGate.swift` (create, added during verification) — pure decision for whether MacLock may watch at all, and the precedence the icon reports. Extracted from `MacLockController` so the logic behind Goal Verification truth 2 is covered by `swift test`.
- `Tests/ProximityCoreTests/MonitoringGateTests.swift` (create, added during verification) — exhaustive combination and precedence tests for that gate.
- `Tests/ProximityCoreTests/ProximityEngineTests.swift` (create) — Swift Testing suite for the engine, including its smoothing behaviour.
- `MacLock/ScreenLocker.swift` (create) — runtime binding of `SACLockScreenImmediate` and the single `lock()` entry point.
- `MacLock/AppSettings.swift` (create) — observable, `UserDefaults`-backed settings store.
- `MacLock/WatchMonitor.swift` (create) — `CBCentralManager` wrapper: discovery, selection, and RSSI sampling in both active and passive modes.
- `MacLock/LaunchAtLogin.swift` (create) — `SMAppService.mainApp` register/unregister wrapper.
- `MacLock/MacLockController.swift` (create) — wires monitor samples into the engine and engine decisions into the locker; owns armed/paused status.
- `MacLock/MenuBarContent.swift` (create) — menu bar icon state and menu items.
- `MacLock/SettingsView.swift` (create) — device picker, live signal readout, calibration sliders, toggles.
- `MacLock/MacLockApp.swift` (modify) — `MenuBarExtra` + `Settings` scenes replacing `WindowGroup`.
- `MacLock/ContentView.swift` (delete) — template placeholder.

## Assumptions

- The Apple Watch to be monitored is signed into the same Apple ID as this Mac, so macOS resolves its rotating private address to a stable identity and `CBPeripheral.identifier` stays constant across launches. Tasks 5, 6 and 8 depend on this. If it does not hold, the saved device selection will stop matching after roughly 15 minutes and the app will behave as though the watch is permanently absent.
- The Mac can open a BLE connection to the watch, which is what active sampling requires. Task 6 depends on this; passive mode is the built-in fallback if it does not hold.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| SwiftPM rejects a target whose `path:` points outside `Sources/`, breaking `swift test` | Low | High — the whole test strategy rests on it | Task 2 proves the layout with a failing-then-passing test before any engine logic is written. If SwiftPM rejects it, move the sources to a conventional `Sources/ProximityCore/` and add an `XCLocalSwiftPackageReference` plus `packageProductDependencies` entry to the app target instead; the engine code is unaffected either way. |
| The same `ProximityCore` sources compile under two different Swift language modes — Swift 5 in the app target, Swift 6 strict concurrency in a freshly authored manifest — so `swift test` and `xcodebuild` disagree about what is valid | Medium | Medium — spurious test-only build failures, or Sendability problems visible in only one build | Task 2 pins the manifest to `swiftLanguageModes: [.v5]`, matching the app target's `SWIFT_VERSION = 5.0`. Both DoD commands run in Task 8, so a divergence cannot pass unnoticed. |
| Active sampling disrupts other Bluetooth peripherals (keyboard, mouse, Personal Hotspot) — a documented, reproducible BLEUnlock failure | Medium | Medium — app becomes unusable for affected users | Passive mode ships in the same task (Task 6) as a user-facing toggle, not a follow-up. |
| Turning Bluetooth off, or an unselected device, is mistaken for the user walking away and locks the Mac | Medium | High — spurious locks destroy trust in the app | The engine only ever locks on evidence; the controller suspends monitoring and clears sample history whenever `CBCentralManager.state` is not `.poweredOn`, no device is selected, or the user has paused (Tasks 6 and 8, Goal Verification truth 2). |
| Stale RSSI history across a system sleep/wake produces an immediate false lock on wake | Medium | Medium | Sample history is cleared whenever monitoring starts or restarts, so the dwell timer begins from a fresh observation (Tasks 2 and 8). |

## Goal Verification

### Truths

1. With a watch selected, monitoring armed and the watch in range, MacLock never locks the Mac — momentary signal dips and brief interference do not produce a lock.
2. MacLock never locks the Mac in any state where it cannot observe the watch: Bluetooth off or unavailable, no device selected, or monitoring paused. Absence of evidence is never treated as evidence of absence.

## E2E Test Scenarios

These drive the built `MacLock.app` directly (Tier 2b of the live-target probe — the artifact is installed, not served). Build and launch with:

```
xcodebuild -project MacLock.xcodeproj -scheme MacLock -configuration Debug build
open "$(xcodebuild -project MacLock.xcodeproj -scheme MacLock -configuration Debug -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2}')/MacLock.app"
```

Steps are performed against the running app; each expected result is observable on screen. Screenshots may be captured with `screencapture -x <path>` and read back as evidence.

### TS-001: First-run setup and device selection
**Priority:** Critical
**Preconditions:** App never launched before (`defaults delete au.com.yumait.MacLock`); Bluetooth on; Apple Watch worn and nearby.
**Mapped Tasks:** Task 1, Task 4, Task 5

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Launch `MacLock.app` | Menu bar icon appears; no icon in the Dock and no app window |
| 2 | Click the menu bar icon, choose Settings | Settings window opens; macOS prompts for Bluetooth permission with MacLock's usage description |
| 3 | Grant Bluetooth permission | Device list begins populating with nearby Apple devices, each showing a live signal value |
| 4 | Select the Apple Watch from the list | Selection is highlighted; the live signal readout tracks that device |
| 5 | Choose Quit from the menu bar menu | The menu bar icon disappears and the MacLock process exits |
| 6 | Relaunch the app, reopen Settings | The same watch is still selected and its live readout resumes |

### TS-002: Walk-away lock
**Priority:** Critical
**Preconditions:** TS-001 complete; monitoring armed; threshold calibrated so the watch reads in-range at the desk.
**Mapped Tasks:** Task 3, Task 6, Task 7, Task 8

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Sit at the Mac wearing the watch, observe the menu bar icon for 60 seconds | Icon stays in the in-range state; the Mac does not lock |
| 2 | Walk out of range wearing the watch | Icon changes to the away state as the smoothed signal drops below the threshold |
| 3 | Remain out of range past the configured delay | The Mac locks and the lock screen is shown |
| 4 | Return and unlock with Apple Watch, Touch ID or password | Desktop returns; icon returns to the in-range state with no user action in MacLock |

### TS-003: Signal-lost lock
**Priority:** High
**Preconditions:** TS-001 complete; monitoring armed; watch in range.
**Mapped Tasks:** Task 2, Task 6, Task 8

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Power the watch off (or enable its aeroplane mode) while sitting at the Mac | Signal readout stops updating; icon shows the signal-lost state |
| 2 | Wait past the configured no-signal timeout | The Mac locks |
| 3 | Confirm the lock happened on the no-signal path, not the threshold path | The delay matches the no-signal timeout, not the shorter away delay |

### TS-004: Monitoring cannot lock without evidence
**Priority:** High
**Preconditions:** TS-001 complete.
**Mapped Tasks:** Task 4, Task 8

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Choose Pause from the menu bar, then walk out of range for twice the no-signal timeout | Icon shows the paused state; the Mac does not lock |
| 2 | Return, choose Resume | Icon returns to the in-range state and monitoring continues |
| 3 | Turn Bluetooth off at the system level while armed and at the desk, wait past the no-signal timeout | Icon shows a distinct Bluetooth-unavailable state; the Mac does **not** lock |
| 4 | Turn Bluetooth back on | Monitoring resumes and the icon returns to the in-range state |

### TS-005: Lock Screen Now
**Priority:** Medium
**Preconditions:** App running.
**Mapped Tasks:** Task 3

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | Choose "Lock Screen Now" from the menu bar | The Mac locks immediately and requires a password, Touch ID or watch to return |

## Progress Tracking

- [x] Task 1: Turn the template into a menu bar utility shell
- [x] Task 2: ProximityCore — the RSSI-to-lock-decision engine
- [x] Task 3: Screen locker and Lock Screen Now
- [x] Task 4: Persisted settings store
- [x] Task 5: Bluetooth device discovery and selection
- [x] Task 6: RSSI sampling in active and passive modes
- [x] Task 7: Calibration and preferences UI
- [x] Task 8: Arm the auto-lock

## Implementation Tasks

### Task 1: Turn the template into a menu bar utility shell

**Objective:** Reconfigure the Xcode target from a sandboxed windowed app into an unsandboxed menu bar utility, and replace the SwiftUI template scene with a `MenuBarExtra` that shows a static icon and a Quit item. This establishes the app shape every later task builds on and removes the placeholder view. Verified by TS-001 steps 1–2.

**Files:**

- Modify: `MacLock.xcodeproj/project.pbxproj`
- Modify: `MacLock/MacLockApp.swift`
- Delete: `MacLock/ContentView.swift`

**Key Decisions / Notes:**

- Set in **both** the Debug and Release `XCBuildConfiguration` blocks (around `MacLock.xcodeproj/project.pbxproj:256` and `:288`): `ENABLE_APP_SANDBOX = NO`, `INFOPLIST_KEY_LSUIElement = YES`, `INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.utilities"`, and `INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription` with copy explaining that MacLock uses Bluetooth to sense whether the selected Apple Watch is nearby.
- The target uses `PBXFileSystemSynchronizedRootGroup` (`MacLock.xcodeproj/project.pbxproj:15`), so deleting `ContentView.swift` from disk removes it from the build and no new file needs registering. Do not add `PBXFileReference` or `PBXBuildFile` entries for source files anywhere in this plan.
- `MacLock/MacLockApp.swift:12-16` replaces its `WindowGroup` with `MenuBarExtra`. The `Settings` scene is added in Task 7; this task only needs the icon and Quit.
- Confirm the chosen SF Symbol actually renders before committing to it — a wrong name produces a blank menu bar item, not an error.
- Values in `## Global Constraints` bind this task; do not restate them here.

**Definition of Done:**

- [x] `MacLock.app` launches with an icon in the menu bar, no Dock icon and no window.
- [x] The menu bar item opens a menu containing a working Quit item.
- [x] The built app's `Info.plist` contains `LSUIElement`, `NSBluetoothAlwaysUsageDescription` and `LSApplicationCategoryType`, and its entitlements no longer request the App Sandbox.
- [x] Verify: `xcodebuild -project MacLock.xcodeproj -scheme MacLock -configuration Debug build`

### Task 2: ProximityCore — the RSSI-to-lock-decision engine

**Objective:** Build the pure logic that turns a stream of timestamped RSSI samples into lock decisions, with a SwiftPM package wrapping it so the whole thing is testable from the command line. This is the heart of the app and the only part with non-trivial algorithmic behaviour, so it is written test-first and kept entirely free of CoreBluetooth and AppKit.

**Files:**

- Create: `Package.swift`
- Create: `.gitignore`
- Create: `MacLock/ProximityCore/ProximityEngine.swift`
- Create: `MacLock/ProximityCore/RSSISmoother.swift`
- Test: `Tests/ProximityCoreTests/ProximityEngineTests.swift`

**Key Decisions / Notes:**

- `Package.swift` declares `ProximityCore` with `path: "MacLock/ProximityCore"` and a test target with `path: "Tests/ProximityCoreTests"`. The Xcode project never references this manifest — the app compiles the same sources through its synchronized group, so app code uses the types directly and must **not** `import ProximityCore`. Types the tests exercise need `public` or `@testable` access.
- **Pin the manifest to `swiftLanguageModes: [.v5]`** so both compilations of these files agree. The app target is fixed at Swift 5 language mode by `## Global Constraints`, while a manifest authored on the Swift 6.3 toolchain defaults to Swift 6 mode with strict concurrency checking — leaving it unpinned means the same source is checked under two different regimes, and `swift test` can fail on concurrency diagnostics that have nothing to do with the engine.
- `SHORTCUT:` sources shared between the app target and the package rather than linked as a real dependency — convert to a conventional `Sources/ProximityCore/` layout with an `XCLocalSwiftPackageReference` if `ProximityCore` ever needs a third-party dependency of its own.
- The repository has no `.gitignore` and `swift test` creates build output at the root, so add one covering SwiftPM's `.build/` and `.swiftpm/` alongside Xcode's `DerivedData/`. Do not add rules for anything already tracked — `MacLock.xcodeproj/xcuserdata/` is committed today and changing that is outside this plan.
- Write the manifest and one failing test first, and confirm `swift test` compiles and fails for the right reason, before any engine logic — that single step also settles the Risks-table question about the custom `path:`.
- The engine takes time as an input (samples carry timestamps, and a tick advances the clock); it must never read the wall clock itself, or the dwell and timeout behaviours become untestable.
- Required behaviours: a moving average over recent samples; a lock decision when the smoothed value stays below the threshold continuously for the away delay; a *separate* lock decision when no sample arrives for the no-signal timeout; the away timer resets if the smoothed value recovers before the delay elapses; a reset that clears all history so the next observation starts a fresh dwell.
- Repeat locks are suppressed by an explicit "screen is currently locked" input that the caller sets, **not** by remembering that a decision was already emitted. The engine stays silent while that input is true and re-arms when it goes false. Emission-based suppression would consume the app's one lock decision even when the lock did not take effect, leaving the Mac unlocked and the engine quiet until the watch returned — the exposure hole the Codex review identified. Keeping it an input also keeps the rule testable without any screen present.
- Starting defaults, all user-tunable in Task 7: threshold -75 dBm, away delay 5 s, no-signal timeout 30 s, smoothing window 5 samples.
- Assertions must target the decision the engine returns, not its internal counters. For each behaviour, check that a one-value change to the implementation would actually fail the test.

**Definition of Done:**

- [x] A sustained run of samples below the threshold produces exactly one lock decision, and only after the away delay has elapsed.
- [x] A dip below the threshold that recovers before the away delay produces no lock decision.
- [x] Silence for longer than the no-signal timeout produces a lock decision distinguishable from the away-threshold one.
- [x] While the "screen is locked" input is true, continued out-of-range samples produce no further decisions; clearing that input while still out of range produces a fresh decision.
- [x] A lock decision followed by the "screen is locked" input staying false produces another decision — a lock that did not take effect does not silence the engine.
- [x] Resetting the engine clears history so a subsequent below-threshold sample starts the away delay afresh rather than locking immediately.
- [x] A single outlier sample in an otherwise in-range series does not cross the threshold, demonstrating the smoothing.
- [x] `git status --short` is clean of SwiftPM build output after a test run.
- [x] Verify: `swift test`

### Task 3: Screen locker, lock-state observation, and Lock Screen Now

**Objective:** Bind the private `SACLockScreenImmediate` symbol at runtime, observe the system's real screen-lock state, and surface a "Lock Screen Now" menu item. The menu item makes the lock path independently verifiable long before any Bluetooth code exists, and the observed lock state is what later tasks use to know a lock actually took effect. Verified by TS-005.

**Files:**

- Create: `MacLock/ScreenLocker.swift`
- Modify: `MacLock/MacLockApp.swift`

**Key Decisions / Notes:**

- The dlopen path, symbol name, C signature and lock-state notification names are all fixed in `## Global Constraints`. Resolve the handle and symbol once at startup and reuse them; do not re-resolve per lock.
- The function returns `void`, so the *call* yields no success signal. Success is observed instead: the `com.apple.screenIsLocked` notification is the confirmation. Expose both the lock action and the current observed lock state from this type.
- **Symbol resolution failure is a hard, startup-visible error, not a per-call one.** If `dlopen` or `dlsym` fails, MacLock cannot lock at all and must say so prominently and refuse to arm (Task 8) rather than sitting in the menu bar pretending to guard the Mac. Because that check happens once, there is no per-call failure state to retry against.
- Do not add a screensaver or display-sleep fallback: the PRD chose the direct lock precisely because setting-dependent alternatives give a weaker guarantee.
- **Rejected during review:** a bounded-backoff retry loop around the lock call, with injected-locker unit tests for timeout/retry/eventual-success. `SACLockScreenImmediate` is the same primitive the system's own Lock Screen menu item uses; once the symbol resolves there is no realistic per-call failure to retry, and the exposure hole that recommendation targeted is closed instead by Task 8 keying its suppression on observed lock state. A retry state machine for an unreachable failure mode is cost without cover.

**Definition of Done:**

- [x] Choosing "Lock Screen Now" locks the Mac immediately and returning requires a password, Touch ID or Apple Watch.
- [x] The observed lock state flips to locked when the screen locks — by this menu item, by the system's own Lock Screen, or by the screensaver — and back to unlocked on return.
- [x] Symbol-resolution failure is surfaced and blocks arming: verified once by temporarily changing the `dlsym` symbol name to one that does not exist, rebuilding, confirming the error is visible and the app refuses to arm, then reverting.
- [x] Verify: `xcodebuild -project MacLock.xcodeproj -scheme MacLock -configuration Debug build`

### Task 4: Persisted settings store

**Objective:** Add the observable, `UserDefaults`-backed store holding the selected device, the three tuning values, the sampling mode and the paused flag, so every later task reads and writes configuration through one place and settings survive relaunch. Verified by TS-001 step 5.

**Files:**

- Create: `MacLock/AppSettings.swift`

**Key Decisions / Notes:**

- Stored values: selected device identifier and its display name, lock threshold in dBm, away delay in seconds, no-signal timeout in seconds, passive-mode flag, paused flag, launch-at-login flag.
- Defaults on first run are the starting values listed in Task 2; passive mode off, paused off.
- The store is the single source of truth for configuration — no other type may read these keys from `UserDefaults` directly.
- SwiftUI views observe this store, so it must publish changes; the tuning sliders in Task 7 depend on that.
- Keep this store free of CoreBluetooth types — it stores an identifier, not a peripheral.

**Definition of Done:**

- [x] Changing any stored value and relaunching the app restores the changed value, not the default.
- [x] A first run with no saved preferences yields the documented defaults.
- [x] Verify: `xcodebuild -project MacLock.xcodeproj -scheme MacLock -configuration Debug build`

### Task 5: Bluetooth device discovery and selection

**Objective:** Add the `CBCentralManager` wrapper that scans for nearby devices and a Settings window listing them with live signal values, so the user can identify their watch by watching the number move and select it. Selection persists through the Task 4 store. Verified by TS-001 steps 2–5.

**Files:**

- Create: `MacLock/WatchMonitor.swift`
- Create: `MacLock/SettingsView.swift`
- Modify: `MacLock/MacLockApp.swift`

**Key Decisions / Notes:**

- `MacLock/MacLockApp.swift` gains a `Settings` scene alongside the `MenuBarExtra` from Task 1, and the menu gains an item that opens it. A window rather than a popover is required: the calibration flow in Task 7 has the user walk away while watching the readout, and a popover dismisses on focus loss.
- Discovery lists devices reporting a name, so the watch is identifiable; devices appearing only as identifiers are noise for this product and are filtered out.
- Persist `CBPeripheral.identifier` — the system-assigned UUID, stable for a same-Apple-ID device — and recover the peripheral on later launches with `retrievePeripherals(withIdentifiers:)` rather than by re-scanning and name-matching.
- Surface `CBCentralManager.state` in the UI. Bluetooth off or unauthorised must read as a clear message, not an empty list.
- Continuous RSSI updates during a scan need duplicate discovery events enabled; without that, a device is reported once and the readout freezes.
- Scanning is a hot path — the list is rebuilt on every advertisement, so avoid re-sorting or re-allocating the whole list per event.

**Definition of Done:**

- [x] Opening Settings triggers the macOS Bluetooth permission prompt showing MacLock's usage description on first run.
- [x] Nearby named Apple devices appear in the list, each with a signal value that visibly changes as the device is moved.
- [x] Selecting a device persists it; quitting and relaunching shows the same device still selected.
- [ ] With Bluetooth switched off, the window states that Bluetooth is unavailable rather than showing an empty list. **Deferred to the final user-assisted pass** (with TS-004): `blueutil` is not installed and `tccutil reset Bluetooth` is SIP-blocked, so the only ways to reach this state are a manual radio toggle or Control Centre automation, and toggling the radio cuts the user's Bluetooth headphones.
- [x] Verify: `xcodebuild -project MacLock.xcodeproj -scheme MacLock -configuration Debug build`

### Task 6: RSSI sampling in active and passive modes

**Objective:** Extend the monitor to produce a continuous stream of RSSI samples for the selected device by two routes — connecting and polling, or observing advertisements — with a user toggle to choose between them. Active is the default because it gives a steady sample rate and an immediate disconnect signal; passive exists because active polling is documented to disrupt other Bluetooth peripherals.

**Files:**

- Modify: `MacLock/WatchMonitor.swift`
- Modify: `MacLock/SettingsView.swift`

**Key Decisions / Notes:**

- Active mode connects to the selected peripheral and polls its RSSI about once a second, re-establishing the connection if it drops. Passive mode scans for advertisements and takes the RSSI each one carries. Both paths emit the same timestamped sample type, so the Task 2 engine and the Task 7 readout are indifferent to which is running.
- Switching mode at runtime must tear down the previous path completely — leaving an active connection open while scanning is exactly the interference the toggle exists to avoid.
- Losing the connection in active mode is not by itself a lock trigger; it stops samples arriving, and the engine's no-signal timeout decides. Keeping that judgement in one place is what stops the two lock paths from disagreeing.
- Sampling stops whenever Bluetooth is unavailable, no device is selected, or monitoring is paused; the app publishes which of those it is so Task 8 can show it and Task 7 can explain it.

**Definition of Done:**

- [x] With a device selected in active mode, a fresh signal value arrives at roughly one-second intervals and tracks distance as the watch is carried away and back.
- [x] Toggling passive mode continues to produce updating values with no connection held open to the watch.
- [x] Toggling between modes repeatedly leaves exactly one sampling path running each time.
- [ ] Sampling stops and is reported when Bluetooth is turned off, and resumes when it is turned back on. **Deferred to the final user-assisted pass** with the other Bluetooth-radio checks.
- [x] Verify: `xcodebuild -project MacLock.xcodeproj -scheme MacLock -configuration Debug build`

### Task 7: Calibration and preferences UI

**Objective:** Complete the Settings window with the live-feedback threshold slider that makes calibration possible, the two timing controls, the sampling-mode toggle and launch at login. This is what lets the user set "far enough" by feel instead of guessing a number.

**Files:**

- Create: `MacLock/LaunchAtLogin.swift`
- Modify: `MacLock/SettingsView.swift`
- Modify: `MacLock/AppSettings.swift`

**Key Decisions / Notes:**

- The threshold control shows the live *smoothed* value from the Task 2 engine against the chosen cut-off, so the user can walk away and watch the two converge. Showing the raw value instead would be visibly jittery and would not match what the lock decision actually uses.
- Also present: away delay, no-signal timeout, passive-mode toggle, launch at login.
- Launch at login uses `SMAppService.mainApp` — `register()`, `unregister()`, and `status` to reflect the real system state. Registration can fail (an unsigned or relocated build); on failure revert the toggle rather than showing a state the system does not agree with.
- The slider is dragged continuously — recompute only what changed rather than restarting sampling on every value change.
- All labels and help text in Australian English, per `## Global Constraints`.

**Definition of Done:**

- [x] The threshold control displays a live smoothed signal value that moves as the watch is carried away, alongside the chosen threshold.
- [x] Away delay, no-signal timeout and passive mode are adjustable and persist across relaunch.
- [x] Enabling launch at login registers the app as a login item and the toggle reflects the system's actual registration state. (Registration and deregistration both verified; the revert-on-failure branch was not forced, since `register()` cannot be made to fail on a validly signed local build.)
- [x] Verify: `xcodebuild -project MacLock.xcodeproj -scheme MacLock -configuration Debug build`

### Task 8: Arm the auto-lock

**Objective:** Wire the sampling stream into the engine and the engine's decisions into the screen locker, then reflect the resulting state in the menu bar icon and add pause/resume. This is the task that makes the app do its job. Verified by TS-002, TS-003 and TS-004.

**Files:**

- Create: `MacLock/MacLockController.swift`
- Create: `MacLock/MenuBarContent.swift`
- Modify: `MacLock/MacLockApp.swift`

**Key Decisions / Notes:**

- The controller feeds Task 6 samples into the Task 2 engine, drives the engine's clock so the no-signal timeout can fire without any sample arriving, and calls the Task 3 locker on a lock decision. It applies the Task 4 settings and re-applies them when they change.
- It also feeds Task 3's observed lock state into the engine as the repeat-suppression input, so a lock that did not take effect does not consume the decision and leave the Mac exposed. The observed state — not the fact that a lock was requested — is what drives the locked icon.
- If Task 3 could not resolve the lock symbol at startup, the controller refuses to arm and the menu bar shows the error state. An app that cannot lock must not present itself as guarding the Mac.
- Distinct icon states: in range, away, locked, paused, and cannot-monitor (Bluetooth unavailable, no device selected, or the lock symbol unavailable). Cannot-monitor is a first-class state, not a variant of away — conflating them is what produces locks triggered by the app's own blindness (Goal Verification truth 2).
- The engine is reset whenever monitoring starts or restarts — app launch, resume from pause, Bluetooth returning, device changed, system wake — so a stale sample history can never fire an immediate lock. Without this, waking the Mac after a night asleep locks it instantly.
- Pause and resume are menu items and must agree with the paused flag in the Task 4 store, so the state survives relaunch.
- Monitoring continues while the screen is locked, so returning to the desk restores the in-range state with no user action.
- Samples arrive about once a second and drive a menu bar redraw — do not re-render on samples that leave the displayed state unchanged.

**Definition of Done:**

- [x] Carrying the watch out of range past the away delay locks the Mac, and the icon passes through the away state on the way. (Verified by raising the threshold above the live signal, which puts the engine in exactly the away state a walk-away produces: locked after 7.4s against a 5s delay. The physical walk-away is TS-002 in the final user-assisted pass.)
- [x] Sitting at the Mac with the watch in range for several minutes produces no lock and no icon state change. (5-minute soak: 0 spurious locks.)
- [ ] Powering the watch off locks the Mac only after the no-signal timeout, not after the shorter away delay. **Deferred to the final user-assisted pass** (TS-003): requires physically powering the watch off. The engine-level behaviour is covered by `swift test`.
- [x] Pausing prevents locking even when the watch is absent for longer than both timers; resuming restores monitoring. (Verified with the threshold raised so the engine considered the watch away: zero locks in 60s while paused, locked 7.4s after unpausing.)
- [ ] Turning Bluetooth off while armed shows the unavailable state and does **not** lock the Mac, however long it stays off. **Deferred to the final user-assisted pass** (TS-004): needs a radio toggle, which would cut the user's Bluetooth headphones.
- [x] Unlocking after an automatic lock returns the icon to the in-range state without any interaction with MacLock.
- [x] Verify: `xcodebuild -project MacLock.xcodeproj -scheme MacLock -configuration Debug build` followed by `swift test`

## Post-Verification Changes

After the plan was marked VERIFIED the user supplied custom artwork, which replaces the SF Symbols the menu bar used.

- `MacLock/Assets.xcassets/Menu.imageset` (a display with signal waves) and `Error.imageset` (a display with a warning triangle), both marked `template-rendering-intent: template` with `preserves-vector-representation`, so the menu bar tints them for the current appearance.
- `MacLock/AppIcon.icon` (Icon Composer) replaces `AppIcon.appiconset`, and the accent colour changed.
- **Consequence for Task 8's icon states:** five distinct glyphs collapse to two assets. `Error` covers the fault states (`cannotLock`, `cannotMonitor`); `Menu` covers everything else, drawn at 45% strength whenever MacLock is not actually guarding (`paused`, `noDevice`). In-range, away and locked therefore share one glyph and are distinguished by the menu's status line rather than the icon.
- Size and dimming are baked into the `NSImage`: `MenuBarExtra` renders its label into the status item and ignores SwiftUI `.frame` and `.opacity` on it (both verified ignored before switching approach).
