//
//  SettingsView.swift
//  MacLock
//

import SwiftUI

/// Device selection and calibration, and the networks MacLock stands down on.
///
/// This is a window rather than a popover on purpose: calibrating the threshold
/// means walking away while watching the live reading, and a popover closes the
/// moment it loses focus.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    var monitor: WatchMonitor
    var wifi: WiFiMonitor
    var controller: MacLockController

    /// Whether the device list is expanded past ``collapsedDeviceLimit``.
    @State private var showsAllDevices = false

    var body: some View {
        TabView {
            watchTab
                .tabItem { Label("Watch", systemImage: "applewatch") }

            TrustedNetworksView(settings: settings, wifi: wifi)
                .tabItem { Label("Networks", systemImage: "wifi") }
        }
        .frame(width: 520, height: 640)
    }

    /// A grouped form rather than a stack of headings and rules: the sections are
    /// what the system draws for settings, and letting the form own the one scroll
    /// view means the device list no longer scrolls inside a page that also scrolls.
    private var watchTab: some View {
        Form {
            Section {
                StatusHeader(status: controller.status)
                    .padding(.vertical, 2)
            }

            deviceSection

            calibrationSection

            optionsSection
        }
        .formStyle(.grouped)
        .onAppear {
            monitor.startScanning()
            settings.launchAtLogin = LaunchAtLogin.isEnabled
        }
        .onDisappear { monitor.stopScanning() }
    }

    // MARK: - Devices

    @ViewBuilder
    private var deviceSection: some View {
        Section {
            if let unavailability = monitor.unavailability {
                Label(unavailability.message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if deviceRows.isEmpty {
                Label("Looking for nearby devices…", systemImage: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleDeviceRows) { row in
                    deviceRow(row)
                }

                if deviceRows.count > Self.collapsedDeviceLimit {
                    Button(showsAllDevices
                           ? "Show fewer"
                           : "Show all \(deviceRows.count) nearby devices") {
                        showsAllDevices.toggle()
                    }
                    .buttonStyle(.link)
                }
            }

            SectionCaption("Move your watch closer and further away - the device whose signal changes with it is the one to choose.")
        } header: {
            Text("Your Watch")
        }
    }

    /// How many devices the list shows before it offers to show the rest.
    ///
    /// The list is inside the page's own scroll view rather than a scroller of its
    /// own, so an unbounded one in a busy radio environment would push calibration
    /// off the bottom -- and calibrating means watching the meter while you walk
    /// away, which you cannot do if reaching it means scrolling past thirty
    /// doorbells.
    private static let collapsedDeviceLimit = 5

    /// One row per device, plus a row for a watch that is chosen but not currently
    /// being heard.
    ///
    /// Without that extra row a selected watch that walks out of range vanishes from
    /// the panel entirely, which reads as "MacLock forgot my watch" at exactly the
    /// moment the user is checking whether it still knows about it.
    ///
    /// The chosen watch is hoisted to the top. The monitor sorts by name so rows do
    /// not reorder themselves while you read them, and hoisting one pinned row keeps
    /// that true -- it moves only when you choose a different watch -- while making
    /// sure the collapsed list can never hide the device you already picked.
    private var deviceRows: [DeviceRow] {
        var rows = monitor.discovered.map {
            DeviceRow(id: $0.id, name: $0.name, rssi: $0.rssi)
        }

        guard let id = settings.selectedDeviceID else { return rows }

        if let index = rows.firstIndex(where: { $0.id == id }) {
            rows.insert(rows.remove(at: index), at: 0)
        } else {
            rows.insert(
                DeviceRow(id: id, name: settings.selectedDeviceName ?? "Selected watch", rssi: nil),
                at: 0
            )
        }
        return rows
    }

    private var visibleDeviceRows: [DeviceRow] {
        let rows = deviceRows
        guard !showsAllDevices, rows.count > Self.collapsedDeviceLimit else { return rows }
        return Array(rows.prefix(Self.collapsedDeviceLimit))
    }

    /// Each row is a button rather than a `List` selection binding. List selection
    /// competes with row-level gestures and depends on window focus; a button fires
    /// on the click it is given.
    private func deviceRow(_ row: DeviceRow) -> some View {
        let isSelected = settings.selectedDeviceID == row.id

        return Button {
            settings.selectedDeviceID = row.id
            settings.selectedDeviceName = row.name
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .imageScale(.large)

                Text(row.name)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                if let rssi = row.rssi {
                    SignalBars(rssi: rssi)
                    Text("\(rssi) dBm")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Text("no signal")
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            // The label is a stack of views, which leaves the button nameless to
            // VoiceOver unless the stack is collapsed into one element first.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(row.name)
            .accessibilityValue(row.rssi.map { "\($0) dBm" } ?? "no signal")
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Calibration

    /// The threshold control shows the *smoothed* signal, which is the value the
    /// lock decision actually uses. Showing the raw reading would jitter by 10-20
    /// dBm and give the user a target they cannot aim at.
    ///
    /// Slider and meter share one dBm range, so the mark on the bar sits under the
    /// knob that sets it: the two numbers that used to live in separate rows are now
    /// one picture.
    private var calibrationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Lock below") {
                    Text("\(settings.lockThreshold) dBm")
                        .monospacedDigit()
                }

                Slider(
                    value: Binding(
                        get: { Double(settings.lockThreshold) },
                        set: { settings.lockThreshold = Int($0.rounded()) }
                    ),
                    in: Double(AppSettings.Limits.threshold.lowerBound)...Double(AppSettings.Limits.threshold.upperBound)
                )
                // A form reserves its leading column for a control's label, which
                // would leave the slider spanning half the row while the meter
                // beneath it spans all of it -- and the meter's mark is meant to
                // line up with this knob.
                .labelsHidden()
                .accessibilityLabel("Lock threshold")

                SignalMeter(reading: controller.smoothedRSSI, threshold: settings.lockThreshold)

                LabeledContent("Smoothed signal now") {
                    if let smoothed = controller.smoothedRSSI {
                        Text("\(smoothed) dBm")
                            .monospacedDigit()
                            .foregroundStyle(smoothed < settings.lockThreshold ? Color.orange : Color.green)
                    } else {
                        Text("waiting")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
            .padding(.vertical, 2)

            Stepper(value: $settings.awayDelay, in: AppSettings.Limits.awayDelay, step: 1) {
                LabeledContent("Wait after the signal drops") {
                    Text("\(Int(settings.awayDelay))s")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Stepper(value: $settings.noSignalTimeout, in: AppSettings.Limits.noSignalTimeout, step: 5) {
                LabeledContent("Lock after no signal at all") {
                    Text("\(Int(settings.noSignalTimeout))s")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            SectionCaption("The bar is the signal your watch is sending right now, and the mark on it is the threshold set above. MacLock starts counting down once the bar falls short of the mark.")
        } header: {
            Text("When to Lock")
        }
    }

    // MARK: - Options

    private var optionsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Passive mode (do not connect to the watch)", isOn: $settings.usePassiveMode)

                Text("Passive mode reads the watch's ordinary broadcasts instead of connecting to it. It updates less often, but it will not disturb other Bluetooth devices such as a keyboard, mouse or Personal Hotspot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)

            Toggle("Open MacLock at login", isOn: launchAtLoginBinding)
        } header: {
            Text("Options")
        }
    }

    /// Reflects the real login-item registration, and reverts if the system refuses.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { wanted in
                if LaunchAtLogin.setEnabled(wanted) {
                    settings.launchAtLogin = wanted
                } else {
                    settings.launchAtLogin = LaunchAtLogin.isEnabled
                }
            }
        )
    }
}

/// A device as the list draws it: the selected watch appears even when nothing is
/// being heard from it, so `rssi` is optional here where the monitor's own type has
/// always just been measured.
private struct DeviceRow: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int?
}
