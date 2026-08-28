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
        VStack(alignment: .leading, spacing: 16) {
            Text("Trusted Networks")
                .font(.headline)

            Text("MacLock stops watching your watch while this Mac is on one of these networks, and starts again as soon as it is not. The menu bar icon dims to show it is no longer guarding.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            currentNetwork

            Divider()

            trustedList

            addByName

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The network this Mac is on, or the reason there is no name to show.
    ///
    /// The reason matters as much as the name: every one of them means MacLock keeps
    /// watching, and a user who cannot see why would read a feature that never
    /// triggers as a broken one.
    @ViewBuilder
    private var currentNetwork: some View {
        if let name = wifi.network.ssid {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Currently on")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(name)
                        .font(.subheadline)
                }
                Spacer()
                Button("Trust This Network") {
                    settings.addTrustedNetwork(name)
                }
                .disabled(settings.trustedNetworks.contains(name))
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label(wifi.network.unavailabilityMessage ?? "", systemImage: "wifi.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if wifi.network == .needsLocationAccess {
                    locationAccessAction
                }
            }
        }
    }

    /// The system prompts once and never again, so a refusal has to be sent to
    /// System Settings rather than offered the same button a second time.
    @ViewBuilder
    private var locationAccessAction: some View {
        switch wifi.locationAccess {
        case .notAsked:
            Button("Grant Location Access...") {
                wifi.requestLocationAccess()
            }
        case .refused:
            Button("Open Location Services Settings...") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices") {
                    NSWorkspace.shared.open(url)
                }
            }
        case .granted:
            EmptyView()
        }
    }

    @ViewBuilder
    private var trustedList: some View {
        if settings.trustedNetworks.isEmpty {
            Text("No trusted networks yet - MacLock watches your watch everywhere.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        } else {
            List {
                ForEach(settings.trustedNetworks, id: \.self) { name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button {
                            settings.removeTrustedNetwork(name)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Stop trusting \(name)")
                    }
                }
            }
            .frame(minHeight: 160)
        }
    }

    private var addByName: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Network name", text: $typedName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTypedNetwork)
                Button("Add", action: addTypedNetwork)
                    .disabled(normalizedNetworkName(typedName) == nil)
            }

            Text("Type a name to trust a network this Mac is not on right now - your office, say. Names are matched exactly, capitals included.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Clears the field only on a name that was actually added, so a blank or
    /// whitespace-only entry cannot look like it worked.
    private func addTypedNetwork() {
        guard settings.addTrustedNetwork(typedName) else { return }
        typedName = ""
    }
}
