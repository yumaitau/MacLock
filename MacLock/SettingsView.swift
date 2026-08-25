//
//  SettingsView.swift
//  MacLock
//

import SwiftUI

/// Device selection and calibration.
///
/// This is a window rather than a popover on purpose: calibrating the threshold
/// means walking away while watching the live reading, and a popover closes the
/// moment it loses focus.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    var monitor: WatchMonitor
    var controller: MacLockController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Watch")
                .font(.headline)

            if let unavailability = monitor.unavailability {
                Label(unavailability.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                deviceList
            }

            selectionSummary

            Text("Move your watch closer and further away - the device whose signal changes with it is the one to choose.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            calibration

            Divider()

            Toggle("Passive mode (do not connect to the watch)", isOn: $settings.usePassiveMode)
                .font(.subheadline)

            Text("Passive mode reads the watch's ordinary broadcasts instead of connecting to it. It updates less often, but it will not disturb other Bluetooth devices such as a keyboard, mouse or Personal Hotspot.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Open MacLock at login", isOn: launchAtLoginBinding)
                .font(.subheadline)
        }
        .padding(20)
        .frame(width: 480, height: 720)
        .onAppear {
            monitor.startScanning()
            settings.launchAtLogin = LaunchAtLogin.isEnabled
        }
        .onDisappear { monitor.stopScanning() }
    }

    /// Each row is a button rather than a `List` selection binding. List selection
    /// competes with row-level gestures and depends on window focus; a button fires
    /// on the click it is given.
    private var deviceList: some View {
        List(monitor.discovered) { device in
            Button {
                settings.selectedDeviceID = device.id
                settings.selectedDeviceName = device.name
            } label: {
                HStack {
                    Image(systemName: settings.selectedDeviceID == device.id ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(settings.selectedDeviceID == device.id ? Color.accentColor : Color.secondary)
                    Text(device.name)
                    Spacer()
                    Text("\(device.rssi) dBm")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 220)
    }

    /// The threshold control shows the *smoothed* signal, which is the value the
    /// lock decision actually uses. Showing the raw reading would jitter by 10-20
    /// dBm and give the user a target they cannot aim at.
    private var calibration: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("When to Lock")
                .font(.headline)

            HStack {
                Text("Lock below")
                Spacer()
                Text("\(settings.lockThreshold) dBm")
                    .monospacedDigit()
            }
            .font(.subheadline)

            Slider(
                value: Binding(
                    get: { Double(settings.lockThreshold) },
                    set: { settings.lockThreshold = Int($0.rounded()) }
                ),
                in: Double(AppSettings.Limits.threshold.lowerBound)...Double(AppSettings.Limits.threshold.upperBound)
            )

            HStack {
                Text("Smoothed signal now")
                Spacer()
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

            Stepper(
                "Wait \(Int(settings.awayDelay))s after the signal drops",
                value: $settings.awayDelay,
                in: AppSettings.Limits.awayDelay,
                step: 1
            )
            .font(.subheadline)

            Stepper(
                "Lock after \(Int(settings.noSignalTimeout))s of no signal at all",
                value: $settings.noSignalTimeout,
                in: AppSettings.Limits.noSignalTimeout,
                step: 5
            )
            .font(.subheadline)
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

    @ViewBuilder
    private var selectionSummary: some View {
        if let name = settings.selectedDeviceName {
            HStack {
                Text("Watching \(name)")
                    .font(.subheadline)
                Spacer()
                if let rssi = monitor.selectedRSSI {
                    Text("\(rssi) dBm")
                        .font(.subheadline)
                        .monospacedDigit()
                } else {
                    Text("no signal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("No watch selected - MacLock will not lock this Mac.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
