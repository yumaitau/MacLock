# Panel UI Rework Buildout

Created: 2026-08-28
Author: josh@luongo.com.au
Agent: Claude Code
Status: VERIFIED
Approved: Yes
Rounds: 2
Worktree: No
Type: Build

## Summary

**Goal:** MacLock's three panels — the Watch settings panel, the Networks settings panel, and the menu bar dropdown — are laid out the way a native macOS 26 app lays out settings: inset grouped sections, label-left/control-right rows, a status header that says what MacLock is doing right now, and no dead space.

**Oracle:** Shown unlabelled beside its `before-*.png` counterpart at the same window size, each reworked panel is the one a viewer picks as the modern, native-looking Mac app. That is the whole of what the user asked for — "cleaner and more modern" — and it is settled by two images side by side, not by any measurement of the code.

**Misfire:** The panels come out looking exactly like System Settings and the app gets *harder* to use — you can no longer tell at a glance whether MacLock is guarding, which watch it is watching, or whether the live signal is above or below the lock threshold; or a state that used to be visible (Bluetooth off, location refused, no watch selected, no trusted networks) is now buried inside a pretty card. Criterion 4 catches the first half by ruling glanceability from a single screenshot; Criterion 5 catches the second by requiring every state and control to still render and still work.

**Constraints:** No behaviour changes to proximity, locking, Wi-Fi monitoring, or Bluetooth scanning — this is the presentation layer only. Every control that exists today survives. macOS 26.5 deployment target. The 31 existing ProximityCore tests stay green.

**Assumed:** The user chose "Settings window + menu bar menu" for scope and "Full rethink of layout" for depth, so restructuring what lives where — a status header, sections regrouped, states surfaced differently — is in scope, while the app's feature set is not.

**Reference:** macOS 26 System Settings, Displays pane — re-obtain with `open "x-apple.systempreferences:com.apple.Displays-Settings.extension" && sleep 4 && screencapture -x -R958,30,723,960 <out>.png`. Saved at `scratchpad/shots/reference-system-settings.png`. The pre-rework panels are captured at `scratchpad/shots/before-watch.png` and `scratchpad/shots/before-networks.png` — the "before" half of the A/B, obtainable only until the first edit lands.

## Acceptance Criteria

Split out of an earlier, more compound set after the build review: each line below carries one claim, so a round that half-succeeds records which half.

- [x] Criterion 1 (ORACLE): Shown unlabelled at the same window size beside its `before-*.png` counterpart, the Watch panel, the Networks panel and the menu bar dropdown are each individually picked as the more modern, native-looking macOS app. Evidence: three separate before/after picks, one recorded per surface, all three required to pass.
- [x] Criterion 2: Every panel presents its content as inset grouped section cards in the System Settings idiom — rounded cards, label-left/control-right rows. Evidence: the after captures ruled against `reference-system-settings.png`.
- [x] Criterion 3: No panel uses a bare horizontal rule as a separator or floating bold text in place of a section header, and every caption sits inside the group it explains rather than floating between groups. Evidence: the after captures.
- [x] Criterion 4: Content fills each panel at its default window size — no empty vertical band taller than one section row (~44pt) between groups, where the before capture of the Watch panel carries a ~150pt one. Evidence: the after captures at the window's default size.
- [x] Criterion 5: From a single screenshot of the menu bar dropdown with nothing clicked, all three are answerable — is MacLock guarding right now, which watch is it watching, and is the live signal above or below the lock threshold. Evidence: that one screenshot.
- [x] Criterion 6: Every control and every state that existed before the rework still renders and still works — the inventory in `## Control Inventory` below, each item exercised against the running app. Evidence: a driven walkthrough recording the observed effect of each.
- [x] Criterion 7: `swift test` passes and `xcodebuild -project MacLock.xcodeproj -scheme MacLock -configuration Debug build` succeeds. Evidence: fresh output of both commands, exit code 0.
- [x] Criterion 8: The changed files introduce no compiler warning that the pre-rework build did not already emit. Evidence: the warning lines from a clean build, compared against the pre-rework baseline.

## Control Inventory

What Criterion 6 is ruled against. Every one of these exists before the rework.

Menu bar dropdown: status text · Pause Monitoring toggle · Lock Screen Now (disabled when the screen cannot be locked) · Settings… · Quit MacLock (⌘Q).

Watch panel: Bluetooth-unavailable message (4 variants) · discovered device list with live dBm · device selection · selection summary with live dBm or "no signal" · no-watch-selected warning · lock threshold slider · live smoothed signal readout with above/below tinting · away-delay stepper · no-signal-timeout stepper · passive mode toggle · open-at-login toggle that reverts if the system refuses.

Networks panel: current network name · Trust This Network (disabled when already trusted) · the 4 unavailability messages · Grant Location Access… · Open Location Services Settings… · trusted list with per-row remove · empty-list message · add-by-name field with Add button disabled on a blank name · field clears only on a name that was actually added.

## Out of Scope

- Proximity, locking, Wi-Fi and Bluetooth behaviour — presentation only.
- The menu bar status icon artwork itself.
- Adding settings that do not exist today.

## Progress Tracking

- [x] Task 1: Signal scale in ProximityCore, test-first
- [x] Task 2: Shared status and signal presentation layer
- [x] Task 3: Menu bar dropdown as a status panel
- [x] Task 4: Watch panel as a grouped form
- [x] Task 5: Networks panel as a grouped form
- [x] Task 6: Drive the real app and capture the after state
- [x] Task 7: Fire the three actions that cannot be fired for real
- [x] Task 8: Prove the open-at-login toggle still reverts on refusal

## Implementation Tasks

### Task 1: Signal scale in ProximityCore, test-first

**Objective:** The one piece of real logic this rework adds — mapping a dBm reading onto a 0...1 position within the app's threshold range, so a meter can draw it. It has edge cases a wrong implementation would render silently wrong (readings outside the range, a reading exactly at the threshold), so it goes in ProximityCore behind unit tests rather than inline in a view.

### Task 2: Shared status and signal presentation layer

**Objective:** The status header and the signal meter are wanted on more than one surface, so they are built once: a presentation of `MacLockController.Status` carrying its symbol, its tint and a human detail line, and a `SignalMeter` view that draws the live smoothed signal against the lock threshold. Both surfaces then read the same thing the same way.

### Task 3: Menu bar dropdown as a status panel

**Objective:** Replace the bare status line and flat button stack with a panel that leads with what MacLock is doing — status, the watch it is watching, the live signal against the threshold — and groups the actions beneath it. This is the surface the user sees most often and currently the one that says least.

### Task 4: Watch panel as a grouped form

**Objective:** Rebuild the Watch settings panel as native grouped sections: a status header, the device list with its empty and unavailable states, calibration built around the signal meter so the threshold and the live reading are visible in one place instead of two rows that cannot be related, and the options. Kill the dead band in the middle.

### Task 5: Networks panel as a grouped form

**Objective:** Rebuild the Networks panel to match — the current network and its permission actions as one group, the trusted list as another with a proper empty state, and adding by name as a third. Remove the nested scroll view the current `List`-inside-`VStack` creates.

### Task 6: Drive the real app and capture the after state

**Objective:** Build, launch and drive the actual app: walk every control in `## Control Inventory`, force the states that do not occur naturally, and capture the after screenshots at the default window size that Criteria 1–4 are ruled from.

### Task 7: Fire the three actions that cannot be fired for real

**Objective:** Criterion 6 failed on three controls that render and are enabled but whose actions were never fired -- Lock Screen Now locks the user's screen, Grant Location Access raises a one-shot system prompt, and Open Location Services Settings opens System Settings. Prove each one still reaches its handler by temporarily substituting the handler with something observable, firing the control from the panel, and observing it. The rework changed how these buttons are built, so "the code looks right" is not evidence that the click still lands.

### Task 8: Prove the open-at-login toggle still reverts on refusal

**Objective:** The binding is supposed to snap back to the real login-item state when the system refuses the change, and the happy path passing says nothing about that. Force `LaunchAtLogin.setEnabled` to refuse, drive the toggle, and observe it revert.

## Round Log

- Round 1 build: all six tasks built. Task 1 went RED first (`signalFraction` missing) then green; suite 31 -> 35. Three defects were found by driving the real app rather than by reading the code, and fixed inside the round: (a) section captions rendered *outside* their group card via the form's `footer:`, where System Settings draws them inside -- replaced with a `SectionCaption` row inside each `Section`; (b) the signal meter's threshold mark was drawn in `.windowBackgroundColor` as a gap in a `.quaternary` track and was invisible on a card, now a darker mark taller than the track; (c) a label-less `Slider` inside a grouped `Form` is laid out in the trailing control column, so it spanned half the row while the meter beneath it spanned all of it -- `.labelsHidden()` makes it span, and the mark now sits directly under the knob. Device rows also gained accessibility labels and values, which the old row buttons never had.
- Round 1 judge: 7/8 pass. Failing: Criterion 6 -- Lock Screen Now, Grant Location Access and Open Location Services Settings all render and are enabled, but none was ever fired, because firing them locks the user's screen, burns a one-shot system prompt, or opens System Settings; and the open-at-login toggle's revert-on-refusal path was never reached. Rendering is not working, so the criterion fails and those four become Tasks 7 and 8.
- Round 1 states driven: no-device, waiting-for-signal, in-range, away, paused, on-trusted-network, and selected-watch-not-heard were all reached on the running app. Bluetooth-unauthorised, Wi-Fi-off, location-not-asked and location-refused cannot be reached without switching off the user's Bluetooth or revoking a system permission, so they were forced by temporarily patching the *data sources* (`WiFiMonitor.readNetwork`, `WatchMonitor.unavailability`) and the one view branch that the real radio kept overwriting, capturing the real views rendering their real branches. Every patched file was restored from a checksummed backup afterwards; `MacLock/WiFiMonitor.swift` and `MacLock/WatchMonitor.swift` are byte-identical to HEAD.

- Round 2: closed Criterion 6. Each destructive or one-shot action was fired for real from the panel with only its *handler* substituted for an observable write, so the click path under test is the shipped one: Lock Screen Now wrote `LOCK_FIRED` (screen never locked), Grant Access wrote `GRANT_FIRED` (no system prompt burned), Open Settings wrote `OPEN_SETTINGS_FIRED` and System Settings opened for real. The open-at-login toggle was driven with `LaunchAtLogin.setEnabled` forced to refuse and stayed off, with no login item registered -- the revert path the happy case says nothing about. Finally `ScreenLocker.availability` was forced to `.unavailable` to render the disabled Lock Screen Now row, which is new `ButtonStyle` code rather than inherited: it greys correctly and reports `enabled=false`, and the header shows the `cannotLock` state. Every patched file was restored from a checksummed backup; `ScreenLocker.swift`, `WiFiMonitor.swift`, `WatchMonitor.swift` and `LaunchAtLogin.swift` are all byte-identical to HEAD.
- Round 2 judge: 8/8 pass.
- Verification: the changes review returned 0 must_fix and 0 should_fix. Of its four suggestions, two were implemented -- the device list is now capped at 5 rows with a "Show all N nearby devices" disclosure (the unbounded list had pushed calibration below the fold at six devices, which breaks the one workflow that needs the device list and the meter on screen together), and the leading-icon metrics in the Networks panel were unified with `StatusHeader`'s. The suggested `IconDetailRow` extraction was declined: its three call sites carry different trailing content -- a spacer, a Trust button, and a conditional permission button -- so a shared container would need a trailing-view generic to serve them, which is more machinery than the duplication costs. Its `cannot_verify` truth about the `.window` interaction model was settled directly: driven through the accessibility API the panel never becomes key and so never dismisses, which is a property of the harness, not the app -- with a real synthesised mouse click it opens on the status item and disappears on an outside click, and Command-Q from the open panel terminates the app.

## Verification Record

- Profile: Full (code with a UI)
- Live target: Tier 2b -- the artifact is an installed app, not a served one. Built with `xcodebuild`, launched from the built product, and driven there. Identity re-asserted before the final captures: binary mtime 19:27:51 against a 19:28:09 capture.
- Commands:
  - `swift test` -- pass (35 tests, 4 suites; 31 before this change)
  - `xcodebuild -project MacLock.xcodeproj -scheme MacLock -configuration Debug clean build` -- pass (BUILD SUCCEEDED)
  - Type checking -- pass (the Swift compiler is this project's type checker; covered by the build)
  - Compiler warnings -- pass (0 Swift warnings; normalised diff against the pre-rework baseline identical)
- Runs at all: launched repeatedly from the built product and driven through both panels and the dropdown. Its own log subsystem is clean over a driven run -- authorisation transitions, `Monitoring state: noDevice`, Wi-Fi joins, no stack traces. One `com.apple.BaseBoard` "task name port right" error appears in the process log at the moments the app was being driven by accessibility automation; it comes from a system framework rather than MacLock's subsystem and was not traced to anything in this diff.
- User-facing paths: snapshot -> interact -> re-snapshot on the running app throughout, using the accessibility API for control-level work and synthesised `CGEvent` mouse clicks where key-window behaviour mattered. Every control in `## Control Inventory` was fired, including the ones whose real effect is destructive or one-shot (see Round 2).
- Reviewers: changes-review 0 must_fix / 0 should_fix / 4 suggestions -- 2 implemented, 1 declined with reasoning, 1 raised as no-action by the reviewer itself. Its one `uncertain` truth was settled directly. Codex companion not enabled for this session.
- Docs: README.md -- four passages updated (the calibration instruction now describes the meter and its mark; the dropdown description now leads with the guarding state; two passages that said "the first line of the menu" corrected for a panel that leads with "Not guarding"). The settings table needed no change: every setting name in it is unchanged.
- Regression: clean build, type check and full suite re-run green after the last review fix landed.

## Not Verified

- **Linting** -- no linter is configured in this project (no SwiftLint or SwiftFormat config in the repository), so there is no lint step to run.
- **Three of the four Bluetooth unavailability strings** -- the `unauthorised` variant was rendered on the running app and captured; `bluetoothOff`, `unsupported` and `starting` are the same row rendering a different `String` from the same enum and were not individually rendered. Reaching them for real means switching off the user's Bluetooth.
- **Two of the four Wi-Fi unavailability strings** -- `wifiOff` and `needsLocationAccess` were rendered and captured; `noHardware` and `notJoined` were not, for the same reason (same row, different string).
- **`SignalMeter`'s own offset-clamping arithmetic** has no automated test. The pure function beneath it (`signalFraction`) is tested against orientation, midpoint, out-of-range clamping and a zero-width range; the view's `min(max(markX - markWidth / 2, 0), width - markWidth)` is covered only by screenshot review, because SwiftUI views are not unit-testable here without a snapshot-testing dependency the project does not have. The changes review raised this itself as no-action.
- **Wi-Fi network name in the captures** -- the screenshots taken during verification show this Mac's real SSID. They live in the session scratchpad, not in the repository.

## Changed Files

- MacLock/ProximityCore/SignalScale.swift (new)
- Tests/ProximityCoreTests/SignalScaleTests.swift (new)
- MacLock/StatusPresentation.swift (new)
- MacLock/SignalMeter.swift (new)
- MacLock/MenuBarContent.swift
- MacLock/MacLockApp.swift
- MacLock/SettingsView.swift
- MacLock/TrustedNetworksView.swift
- README.md
- docs/builds/2026-08-28-rework-panel-ui.md
