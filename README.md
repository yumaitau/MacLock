# MacLock

Locks your Mac when you walk away from it, using your Apple Watch as the key.

macOS already handles the return trip — *Unlock with Apple Watch* — but it has no
walk-away lock. MacLock is the other half: a menu bar utility that watches the
Bluetooth signal of one chosen Apple Watch and locks the screen when it goes out of
range.

## Requirements

- macOS 26.5 or later, on a Mac with Bluetooth Low Energy
- An Apple Watch **signed into the same Apple ID as the Mac**
- Xcode 26.6 (Swift 6.3) to build
- Location access, but only if you want *trusted networks* below

The same-Apple-ID requirement is not a preference. Bluetooth devices rotate their
private address roughly every fifteen minutes to prevent tracking; macOS resolves an
Apple device to its true, stable identity only when it is signed into the same Apple
ID. Without that, the watch you picked would stop matching a quarter of an hour later
and MacLock would behave as though it had vanished.

## Building and running

```sh
xcodebuild -project MacLock.xcodeproj -scheme MacLock -configuration Debug build
open "$(xcodebuild -project MacLock.xcodeproj -scheme MacLock -configuration Debug \
  -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2}')/MacLock.app"
```

MacLock lives only in the menu bar — there is no Dock icon and no main window.

## Setting it up

1. Launch MacLock and grant Bluetooth access when macOS asks.
2. Open **Settings** from the menu bar icon. Nearby devices appear with a live signal
   reading, sorted by name.
3. Find your watch. If several entries look plausible, move the watch closer and
   further away — the one whose number tracks it is yours. Click to select it.
4. Calibrate. Walk to the point where you want the Mac to lock, look at **Smoothed
   signal now**, and set **Lock below** just above that value. The reading turns
   orange once it sits below the threshold, which is the state that starts the
   countdown.

5. Optionally, open **Networks** and name the Wi-Fi networks you do not want guarding
   on. See *Networks you do not need guarding on* below.

Your choice and settings persist across relaunches.

## Settings

| Setting | Default | What it does |
| --- | --- | --- |
| Lock below | -75 dBm | Signal strength at or above which the watch counts as nearby. |
| Wait after the signal drops | 5 s | How long the signal must stay below the threshold before locking. Absorbs momentary dips. |
| Lock after no signal at all | 30 s | Separate, longer timeout for the watch disappearing entirely — powered off, out of radio range, or interfered with. |
| Trusted networks | none | Wi-Fi networks on which MacLock stops watching altogether. |
| Passive mode | off | Read the watch's ordinary broadcasts instead of connecting to it. |
| Open MacLock at login | off | Registers MacLock as a login item. |

The menu also offers **Pause Monitoring** for when the watch is elsewhere but you are
not, and **Lock Screen Now**.

### Active and passive mode

By default MacLock connects to the watch and polls its signal about once a second.
That gives a steady sample rate, but connecting can disturb other Bluetooth devices —
keyboards, mice, Personal Hotspot. If yours start misbehaving, switch on passive mode:
MacLock then only listens to broadcasts the watch already sends. It updates less
often and never holds a connection open.

### Networks you do not need guarding on

At home, a Mac that locks every time you walk to the kitchen is a nuisance rather than
a safeguard. So the **Networks** tab in Settings holds a list of Wi-Fi networks on
which MacLock stops watching entirely: no Bluetooth sampling, and a dimmed menu bar
icon whose first line names the network it has stood down for. Leave that network and
it starts guarding again on the next tick.

Add the network you are on with one click, or type one to trust a network this Mac is
not on right now. Names are matched **exactly**, capitals included, because standing
down means giving up the app's whole job and a network that merely resembles yours is
not good enough evidence to do it on.

This needs **Location access**, which is not a design choice. macOS classes the name of
the network you are joined to as location data: since macOS 14 the system returns no
name at all to an app without that permission. The Networks tab offers a button to
grant it, MacLock never reads a location, and it stops the location service the moment
the permission question is answered.

**If MacLock cannot read the network name, it keeps guarding.** Location access refused,
Wi-Fi switched off, joined to nothing, no Wi-Fi hardware — in every one of those it has
no evidence it is somewhere you trust, and it will not stand down on a guess. Settings
says which of them applies, so a feature that is waiting on a permission never looks
like a feature that is broken.

## Why signal strength, not metres

Bluetooth signal strength is not distance. A stationary watch three metres away
routinely swings ten to twenty dBm as bodies, walls and other radios get in the way. A
setting expressed in metres would be a fiction that miscalibrates itself in every new
room.

So MacLock averages recent readings, compares the smoothed value against a threshold
you set by feel against a live number, and locks only once it has stayed below that
threshold continuously for the configured delay. Three defences against the same false
positive: smoothing, a threshold, and a dwell time.

## What the icon tells you

| Icon | Meaning |
| --- | --- |
| Display with signal waves | Watching your watch |
| The same icon, dimmed | Not watching — paused, or no watch selected |
| Display with a warning triangle | Cannot work: Bluetooth is off or unauthorised, or the lock mechanism is unavailable |

Nearby, away and locked share one glyph; the first line of the menu always spells the
state out.

**MacLock never locks when it cannot see the watch.** Bluetooth switched off, no watch
chosen, monitoring paused — in each of those it has no evidence about where you are,
and it treats absence of evidence as exactly that. A dimmed or warning icon means you
are not being guarded.

## Testing

```sh
swift test
```

The proximity logic — smoothing, threshold, dwell, the no-signal timeout, and the gate
deciding whether MacLock may watch at all — lives in `ProximityCore`, free of
Bluetooth, AppKit and the system clock. Time is an input, so the delays are tested
without waiting on them.

`ProximityCore`'s sources sit under `MacLock/ProximityCore/` and are reached by the
root `Package.swift` through an explicit target path. The Xcode target picks them up
through its file-system-synchronised group, so the same files compile in both places
and neither a test target nor a package reference is needed. The manifest pins Swift 5
language mode to match the app target.

## How it locks

MacLock calls `SACLockScreenImmediate` from the private `login` framework — the same
primitive behind the system's own *Lock Screen* menu item — bound at runtime with
`dlsym`. It returns nothing, so success is never inferred from the call. MacLock
observes the system's `com.apple.screenIsLocked` notification instead, and a lock that
did not take effect does not stop it asking again.

If that symbol cannot be bound, MacLock says so and refuses to arm rather than sitting
in the menu bar pretending to guard the Mac.

Two consequences of that choice: the app is **not sandboxed** and **cannot be
distributed on the Mac App Store**. The App Store-legal alternatives — starting the
screensaver, sleeping the display — only lock if the user's *require password* setting
happens to be right, which is a weaker promise than this app is meant to make.

## Scope

MacLock deliberately does not unlock your Mac. macOS's own *Unlock with Apple Watch*
already does it, and reproducing it would mean storing your login password and
synthesising keystrokes at the login window. It also supports one watch and one Mac,
and only Apple devices resolvable by the same-Apple-ID mechanism above.
