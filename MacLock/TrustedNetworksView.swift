//
//  TrustedNetworksView.swift
//  MacLock
//

import AppKit
import SwiftUI

/// The networks on which MacLock stands down, and the state of the permission that
/// makes reading the current network possible at all.
///
/// It is its own settings tab rather than another section of the watch page: the
/// device list and the calibration readout already fill that window, and a second
/// scrolling list inside it would nest one scroll view in another.
struct TrustedNetworksView: View {
    var settings: AppSettings
    var wifi: WiFiMonitor

    @State private var typedName = ""

    var body: some View {
        Form {
            currentNetworkSection
            trustedListSection
            addByNameSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Current network

    /// The network this Mac is on, or the reason there is no name to show.
    ///
    /// The reason matters as much as the name: every one of them means MacLock keeps
    /// watching, and a user who cannot see why would read a feature that never
    /// triggers as a broken one.
    @ViewBuilder
    private var currentNetworkSection: some View {
        Section {
            if let name = wifi.network.ssid {
                joinedNetworkRow(name)
            } else {
                unavailableNetworkRow
            }
        } header: {
            Text("Current Network")
        }
    }

    private func joinedNetworkRow(_ name: String) -> some View {
        let isTrusted = settings.trustedNetworks.contains(name)

        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: isTrusted ? "wifi.circle.fill" : "wifi.circle")
                .font(.system(size: 24))
                .foregroundStyle(isTrusted ? Color.blue : Color.secondary)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 30, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(isTrusted
                     ? "Trusted - MacLock stands down while you are on this network."
                     : "Not trusted - MacLock keeps watching your watch here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("Trust This Network") {
                settings.addTrustedNetwork(name)
            }
            .disabled(isTrusted)
        }
        .padding(.vertical, 2)
    }

    private var unavailableNetworkRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 30, alignment: .center)
                .accessibilityHidden(true)

            Text(wifi.network.unavailabilityMessage ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if wifi.network == .needsLocationAccess {
                locationAccessAction
            }
        }
        .padding(.vertical, 2)
    }

    /// The system prompts once and never again, so a refusal has to be sent to
    /// System Settings rather than offered the same button a second time.
    @ViewBuilder
    private var locationAccessAction: some View {
        switch wifi.locationAccess {
        case .notAsked:
            Button("Grant Access…") {
                wifi.requestLocationAccess()
            }
        case .refused:
            Button("Open Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices") {
                    NSWorkspace.shared.open(url)
                }
            }
        case .granted:
            EmptyView()
        }
    }

    // MARK: - The list

    @ViewBuilder
    private var trustedListSection: some View {
        Section {
            if settings.trustedNetworks.isEmpty {
                Label("No trusted networks yet - MacLock watches your watch everywhere.", systemImage: "globe")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 2)
            } else {
                ForEach(settings.trustedNetworks, id: \.self) { name in
                    HStack(spacing: 8) {
                        Image(systemName: "wifi")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                            .accessibilityHidden(true)

                        Text(name)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 8)

                        Button {
                            settings.removeTrustedNetwork(name)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                                .imageScale(.large)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Stop trusting \(name)")
                    }
                }
            }

            SectionCaption("MacLock stops watching your watch while this Mac is on one of these networks, and starts again as soon as it is not. The menu bar icon dims to show it is no longer guarding.")
        } header: {
            Text("Trusted Networks")
        }
    }

    // MARK: - Adding by name

    private var addByNameSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField("Network name", text: $typedName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTypedNetwork)

                Button("Add", action: addTypedNetwork)
                    .disabled(normalizedNetworkName(typedName) == nil)
            }
            .padding(.vertical, 2)
            SectionCaption("Trust a network this Mac is not on right now - your office, say. Names are matched exactly, capitals included.")
        } header: {
            Text("Add by Name")
        }
    }

    /// Clears the field only on a name that was actually added, so a blank or
    /// whitespace-only entry cannot look like it worked.
    private func addTypedNetwork() {
        guard settings.addTrustedNetwork(typedName) else { return }
        typedName = ""
    }
}
