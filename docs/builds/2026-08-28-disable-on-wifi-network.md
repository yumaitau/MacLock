# Disable on a Trusted Wi-Fi Network Buildout

Created: 2026-08-28
Author: josh@luongo.com.au
Agent: Claude Code
Status: VERIFIED
Approved: Yes
Rounds: 1
Worktree: No
Type: Build

## Summary

**Goal:** MacLock stops guarding the Mac while it is joined to a Wi-Fi network the user has marked trusted, and resumes the moment it is not.

**Oracle:** With MacLock running and this Mac joined to a trusted network, the menu bar
icon is dimmed and its first line names that network as the reason it is not watching;
remove the network from the list and it goes back to guarding. Observed in the running
app, not inferred from source.

**Misfire:** MacLock could stand down whenever it *cannot read* a network name --
Location access denied, Wi-Fi off, Ethernet-only -- which passes "it does not lock at
home" while silently never guarding anywhere. Criterion 2 catches it: an unreadable or
absent network name must keep MacLock guarding, and Settings must say why the name is
unavailable.

**Constraints:** Standing down is a full stand-down through the existing
`MonitoringGate` -- Bluetooth sampling stops, the icon dims -- not a suppressed lock
with the radio still running. A trusted network never outranks `cannotLock`,
`noDevice` or `paused` in the stand-down precedence. Reading the SSID on macOS 14+
requires Location Services authorization; when it is not granted MacLock keeps
guarding rather than assuming it is home.

**Verification setup:** The live runs use any nearby Bluetooth device selected as
the stand-in watch, with the lock threshold set to its minimum and the no-signal
timeout to its maximum, so exercising the states cannot actually lock this Mac
mid-run. The original settings are restored afterwards.

**Assumed:** Nothing -- the three forks (list vs single network, full stand-down vs
suppressed lock, and whether this Mac can join Wi-Fi for live verification) were all
answered by the user before drafting.

## Acceptance Criteria

- [x] Criterion 1 **[ORACLE]**: With MacLock running and this Mac joined to a Wi-Fi network present in the trusted list, the menu bar's first line names that network as the reason it is not watching, the icon is dimmed, and Settings shows "Smoothed signal now: waiting". Evidence: the running app observed in that state.
- [x] Criterion 2: Removing that network from the trusted list while still connected to it returns MacLock to a guarding state within ~2 s. Evidence: the running app observed before and after the removal.
- [x] Criterion 3 **[MISFIRE GUARD]**: With a non-empty trusted list and no readable network name -- Location access not granted, Wi-Fi off, or associated with nothing -- MacLock keeps guarding. Evidence: the running app in that state, plus a unit test asserting a `nil` SSID is never trusted.
- [x] Criterion 4: In that same unreadable-name state, the Settings window states why the network name is unavailable. Evidence: the running app, Settings window observed.
- [x] Criterion 5: Leaving a trusted network resumes guarding without firing a lock while the Bluetooth signal is being reacquired -- the status passes through "looking for your watch" and no lock is requested. Evidence: the running app driven through that transition with a selected device in range, read from MacLock's own decision log.
- [x] Criterion 6: `swift test` passes, with the monitoring gate's exhaustive combination test covering all five inputs and asserting that a trusted network stands down but never outranks `cannotLock`, `noDevice` or `paused`. Evidence: a fresh `swift test` run.
- [x] Criterion 7: The Settings window adds the network the Mac is currently on to the trusted list with one click. Evidence: the running app.
- [x] Criterion 8: The Settings window accepts a typed network name and removes an existing entry. Evidence: the running app, both actions exercised.
- [x] Criterion 9: The Settings window refuses a blank or whitespace-only entry. Evidence: the running app.
- [x] Criterion 10: The trusted list survives quitting and relaunching MacLock. Evidence: the list observed after a relaunch.
- [x] Criterion 11: `xcodebuild ... build` exits 0 and emits no warnings in the files this run created or changed. Evidence: the build output.
- [x] Criterion 12: The README documents the trusted-network setting and the Location Services requirement it needs. Evidence: the README passage.
- [x] Criterion 13: The README states that an unreadable network name keeps MacLock guarding rather than assuming it is home. Evidence: the README passage.

## Out of Scope

- Matching on BSSID, or distinguishing two networks that share an SSID.
- Trusted *wired* networks, VPN state, or any location signal other than Wi-Fi.
- Scanning for nearby SSIDs to pick from; the user adds the current network or types one.

## Progress Tracking

- [x] Task 1: Pure trusted-network decision and gate input in ProximityCore
- [x] Task 2: WiFiMonitor -- live SSID plus Location authorization
- [x] Task 3: Persist the list and wire it through the controller
- [x] Task 4: Trusted-network section in Settings
- [x] Task 5: Build, drive the running app, document it

## Implementation Tasks

### Task 1: Pure trusted-network decision and gate input in ProximityCore

**Objective:** Add the safety-critical decision as pure, testable code: a network name
that is absent or unreadable is never trusted, and `MonitoringGate` gains a fifth input
whose stand-down reason sits after `paused` and before `cannotMonitor`. Tests first --
this is the branch that decides whether MacLock guards the Mac at all.

### Task 2: WiFiMonitor -- live SSID plus Location authorization

**Objective:** A `@Observable @MainActor` reader for the current Wi-Fi network name,
built on CoreWLAN, that owns the CoreLocation authorization the name is gated behind
and reports in plain words why the name is unreadable when it is. Includes the
`NSLocationWhenInUseUsageDescription` Info.plist key in both build configurations.

### Task 3: Persist the list and wire it through the controller

**Objective:** `AppSettings` gains the trusted-network list, `MacLockController` feeds
the live network name and that list into the monitoring gate, and a new status carries
the network name to the menu. Standing down here must stop Bluetooth sampling through
the existing path, not a second one. The controller also logs each change of monitoring
state and every lock request through `OSLog`, so why MacLock stopped or resumed guarding
is answerable after the fact rather than only while watching the menu bar.

### Task 4: Trusted-network section in Settings

**Objective:** The part the user actually touches: the current network shown live, a
one-click add, a field for typing a network the Mac is not on, removal, and a clear
notice with a way forward when Location access is what is missing.

### Task 5: Build, drive the running app, document it

**Objective:** Build the app, run it, and put it through the states the criteria rule
on -- trusted, not trusted, no readable name, and the transition off a trusted network --
then bring the README into line with what it now does.

## Round Log

- Round 1, Task 1: `isOnTrustedNetwork` / `normalizedNetworkName` added to
  ProximityCore; `MonitoringGate` gained a fifth input with `.trustedNetwork` ranked
  between `paused` and `cannotMonitor`. RED confirmed behaviourally (3 failures showing
  the gate still monitoring on a trusted network) before the branch was added.
  `swift test` 26 tests / 3 suites pass. The Xcode app target does not compile between
  here and Task 3, which owns the `MonitoringInputs` call site.
- Round 1, Tasks 2-4: `WiFiMonitor` reads the SSID through CoreWLAN and owns the
  CoreLocation permission it is gated behind; `AppSettings` persists the list;
  `MacLockController` feeds the gate and logs every monitoring-state change and lock
  request; Settings gained a Networks tab. The trusted-network UI went in its own tab
  rather than the watch page -- that window is a fixed 480x720 already filled by the
  device list and calibration, and a second scrolling list inside it would have nested
  one scroll view in another.
- Round 1, Task 5: the Location prompt never appeared. Root-caused from `locationd`'s
  own log -- "Client has supported the hardened runtime but doesn't have the entitlement,
  not sending #AuthPrompt message to #CoreLocationAgent". The project builds with
  `ENABLE_HARDENED_RUNTIME = YES` and had no entitlements file at all, so macOS
  suppressed the prompt silently, with no dialog and no error. Added
  `MacLock/MacLock.entitlements` with `com.apple.security.personal-information.location`
  and wired `CODE_SIGN_ENTITLEMENTS` into both configurations. Two earlier hypotheses
  were refuted first (app not frontmost; system-wide Location Services off). Without
  this the feature could never have worked for anyone.
- Round 1, Task 5: `requestWhenInUseAuthorization()` alone does not raise the prompt on
  macOS -- a location service has to actually start -- so `requestLocationAccess()`
  starts one at the coarsest accuracy CoreLocation offers and stops it the moment the
  authorization callback arrives. MacLock never reads a location.
- Round 1, changes-review: 2 should_fix, both closed. (1) The README claimed the
  Location prompt appeared on opening the Networks tab when it actually needs a button
  click -- reworded (this had already been corrected before the review landed).
  (2) `AppSettings.addTrustedNetwork` / `removeTrustedNetwork` carried real logic --
  dedup, append, exact-match removal -- that `swift test` could not reach, because
  `AppSettings` lives in the app target. Moved that logic into `ProximityCore` as
  `addingTrustedNetwork` / `removingTrustedNetwork` and covered it: 26 -> 31 tests.
  The reviewer's third finding was `cannot_verify` on the live criteria, which is
  Task 5's job and not a defect.
- Round 1, mutation check on the trusted-network logic: dropping the dedup guard (6
  failures), making removal case-insensitive (4), accepting a blank name (5), and
  treating an unreadable SSID as trusted -- the misfire itself -- (5) were each caught.
- Round 1, Task 5: BLOCKED. Criteria 1, 2, 5 and 7 each need this Mac to be joined to a
  Wi-Fi network, and it is not. `en1` is powered on but `status: inactive`; the Mac
  routes over Ethernet (`en0`), and `networksetup -listpreferredwirelessnetworks en1`
  reports no saved networks, so MacLock cannot join one without credentials. Waited ~35
  minutes. Nine criteria were settled from evidence and are ticked; the four that need a
  real SSID are left unticked rather than ruled from a proxy. This is a blocked
  hand-back under Step 4.6, not a round: no task this run could write would produce a
  Wi-Fi association.
- Round 1, Task 5: the blocker was attacked from four directions before it was accepted,
  not assumed. (1) Waited for the user to join a network -- 35 minutes, then a further
  25-minute watcher, both elapsed with `en1` still `status: inactive`. (2) Joining a
  network directly -- `networksetup -listpreferredwirelessnetworks en1` reports "No
  preferred networks", and no credentials exist for any other. (3) Creating a network via
  Internet Sharing -- needs `sudo`, and `sudo -n true` returns "a password is required".
  (4) Scanning to see what is in range -- the `airport` binary no longer ships on this
  macOS, and `system_profiler` redacts network names without the location privilege the
  scanning process does not hold. Every remaining route needs the user.
- Round 1, Task 5: also tried to close the refused-Location gap in `## Not Verified` by
  revoking the grant and re-answering the prompt with "Don't Allow". `tccutil reset
  Location au.com.yumait.maclock` fails -- Location is a system-scoped TCC service owned
  by locationd, not the per-user database tccutil can rewrite -- so that path stays
  unexercised too. The app was left in its granted, healthy state (authorization 3,
  network `notJoined`, Settings reading "Not connected to a Wi-Fi network.").
- Round 1, Task 5 UNBLOCKED: the user joined a network and the four blocked criteria were
  settled live on `BiteMyShinyMetal2GRouter`. Worth recording that
  `networksetup -getairportnetwork en1` still reported "not associated" the whole time --
  that command is itself redacted on this macOS. `en1` carrying an IP was the tell, and
  MacLock, holding the Location grant, read the name where the shell tool could not. That
  is the feature's own justification, observed from the outside.
- Round 1 judge: 13/13 pass. Oracle -- one click on "Trust This Network" put the live
  network in the list, the menu bar first line became `On "BiteMyShinyMetal2GRouter" -
  not watching`, Settings fell to "Smoothed signal now: waiting" (sampling stopped), and
  the icon dimmed. Removing the entry while still on that network resumed guarding in 1s,
  through "Looking for your watch", with 0 lock requests in MacLock's decision log across
  the whole cycle.
- Round 1: the icon-dimming check was nearly misread. Mean brightness fell from 0.7125
  (guarding) to 0.6819 (trusted), which looks like the wrong direction until you notice
  this menu bar draws a light glyph on blue rather than a dark one on white. Confirmed
  visually at 8x before ruling it: the guarding glyph is crisp white, the trusted one
  fades into the bar.

## Verification Record

- Profile: Full (code with a user-facing UI)
- Live target: Tier 2b -- the artifact is an installed app, not a served one. Built with
  `xcodebuild`, launched from `Build/Products/Debug/MacLock.app`, and driven through the
  real menu bar status item and Settings window via the accessibility API, with
  `screencapture` for visual evidence. Rebuilt and relaunched before each observation, so
  no reading came from a stale bundle.
- Commands:
  - `swift test` -- pass (31 tests, 3 suites)
  - `xcodebuild -configuration Debug build` -- pass (BUILD SUCCEEDED, no warning naming a changed file)
  - `xcodebuild -configuration Release build` -- pass (BUILD SUCCEEDED)
  - mutation check on the trusted-network logic -- pass (4 of 4 caught, including treating
    an unreadable SSID as trusted, which is the misfire itself)
- Types/lint: this project has no separate type-checker or linter; `xcodebuild` is the
  type check, and both configurations are green.
- Runs at all: yes -- launched repeatedly, driven through every reachable state
  (`noDevice`, `waitingForSignal`, `inRange`, `onTrustedNetwork`), decision log read each time.
- User-facing paths: menu bar status item and both Settings tabs driven live; device
  selection, trust-current-network, typed add, remove, blank rejection, relaunch
  persistence, and the trusted/untrusted transition all exercised in the running app.
- Reviewers: build-review 5 should_fix, all closed before the contract locked ·
  changes-review 2 should_fix, both closed (README accuracy; untested list logic moved
  into ProximityCore and covered)
- Docs: README.md -- new "Networks you do not need guarding on" section, plus Requirements,
  Setting it up, Settings table, icon table, safety paragraph and Testing section
- Shortcut debt: none added by this run (the repo's only `SHORTCUT:` marker is the
  pre-existing one in `Package.swift`)
- Regression: `swift test` and both build configurations re-run green after the last change

## Not Verified

- **The refused-Location path was not exercised.** Where access is denied, Settings offers
  "Open Location Services Settings..."; that branch never rendered. Revoking the grant to
  re-answer the prompt was attempted and refused -- `tccutil reset Location
  au.com.yumait.maclock` reports "Failed to reset Location approval status", because
  Location is a system-scoped TCC service rather than one in the per-user database.
  Changing it needs System Settings or `sudo`, neither available to this run. The
  `notAsked` and `granted` branches were both exercised live.
- **No Apple Watch was used.** A neighbouring Bluetooth device stood in as the selected
  watch, in passive mode, with a lock threshold that could not fire. This exercises the
  gate and the sampling lifecycle, which is what the trusted-network feature touches, but
  it does not exercise a real walk-away lock. That behaviour predates this change and was
  not modified.
- **One network, one Mac.** Matching was verified against a single live SSID
  (`BiteMyShinyMetal2GRouter`). Multi-entry matching, and names differing only by case or
  whitespace, are covered by unit tests rather than live.

## Changed Files

- MacLock/ProximityCore/TrustedNetworks.swift (new)
- MacLock/ProximityCore/MonitoringGate.swift
- Tests/ProximityCoreTests/TrustedNetworksTests.swift (new)
- Tests/ProximityCoreTests/MonitoringGateTests.swift
- MacLock/WiFiMonitor.swift (new)
- MacLock/TrustedNetworksView.swift (new)
- MacLock/MacLock.entitlements (new)
- MacLock/AppSettings.swift
- MacLock/MacLockController.swift
- MacLock/MacLockApp.swift
- MacLock/SettingsView.swift
- MacLock.xcodeproj/project.pbxproj
- README.md
