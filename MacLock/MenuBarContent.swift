//
//  MenuBarContent.swift
//  MacLock
//

import AppKit
import SwiftUI

/// The panel behind the status icon.
///
/// This is the surface the user actually looks at, and a list of four commands was
/// the one thing it could not answer: whether the Mac is being guarded right now.
/// So the panel leads with the state, then the watch and its signal against the lock
/// threshold, and only then the things you can do.
struct MenuBarContent: View {
    @Bindable var settings: AppSettings
    var controller: MacLockController
    var screenLocker: ScreenLocker

    var body: some View {
        VStack(spacing: 10) {
            PanelCard {
                StatusHeader(status: controller.status)

                if settings.selectedDeviceName != nil {
                    watchReadout
                }
            }

            PanelCard(padding: 4) {
                PanelToggleRow(
                    title: "Pause Monitoring",
                    systemImage: "pause.circle",
                    isOn: $settings.isPaused
                )

                PanelButtonRow(
                    title: "Lock Screen Now",
                    systemImage: "lock",
                    action: screenLocker.lock
                )
                .disabled(screenLocker.availability != .available)
            }

            PanelCard(padding: 4) {
                SettingsLink {
                    PanelRowLabel(title: "Settings…", systemImage: "gearshape")
                }
                .buttonStyle(PanelRowButtonStyle())

                PanelButtonRow(title: "Quit MacLock", systemImage: "power") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(10)
        .frame(width: 300)
    }

    /// Which watch, how strong its signal is, and where that sits relative to the
    /// threshold -- the three things the old status line left the user to open
    /// Settings for.
    @ViewBuilder
    private var watchReadout: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(settings.selectedDeviceName ?? "")
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                if let smoothed = controller.smoothedRSSI {
                    SignalBars(rssi: smoothed)
                    Text("\(smoothed) dBm")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Text("no signal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            SignalMeter(reading: controller.smoothedRSSI, threshold: settings.lockThreshold)

            Text("Locks below \(settings.lockThreshold) dBm")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// A rounded group, the same shape the settings panels get from a grouped form.
///
/// The panel groups its rows this way rather than separating them with rules: a
/// menu's dividers are what made the old one look like a menu from a decade ago.
private struct PanelCard<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
    }
}

/// Icon, title, and whatever the caller puts on the right.
private struct PanelRowLabel: View {
    var title: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// Highlights on hover the way a menu item does, which a plain button does not.
private struct PanelRowButtonStyle: ButtonStyle {
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.35 : (isHovering && isEnabled ? 0.18 : 0)))
            )
            .onHover { isHovering = $0 }
    }
}

private struct PanelButtonRow: View {
    var title: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            PanelRowLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(PanelRowButtonStyle())
    }
}

private struct PanelToggleRow: View {
    var title: String
    var systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            PanelRowLabel(title: title, systemImage: systemImage)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}
