//
//  WiFiMonitor.swift
//  MacLock
//

import CoreLocation
import CoreWLAN
import Foundation
import OSLog

/// Reports which Wi-Fi network this Mac is on, or why it cannot say.
///
/// macOS classes the name of the network you are joined to as location data. Since
/// macOS 14 `CWInterface.ssid()` returns `nil` unless the app holds Location Services
/// authorisation, whatever the Wi-Fi state actually is. So this type owns the
/// CoreLocation permission as well as the CoreWLAN read: without both, the answer it
/// gives would be indistinguishable from "not on Wi-Fi", and MacLock would stand down
/// somewhere it has never been.
///
/// Everything it publishes is therefore a *reason*, not a bare optional. A caller that
/// only wanted a name would have no way to tell "definitely not on a trusted network"
/// apart from "cannot tell", and those two must not lead to the same decision.
@Observable
@MainActor
final class WiFiMonitor: NSObject {

    /// What MacLock currently knows about the Wi-Fi network.
    enum Network: Equatable {
        /// Joined to this network. The only case that can match a trusted entry.
        case joined(String)
        /// This Mac has no Wi-Fi interface at all.
        case noHardware
        /// macOS will not reveal the name until Location access is granted.
        case needsLocationAccess
        /// Wi-Fi is switched off.
        case wifiOff
        /// Wi-Fi is on, but not associated with any network.
        case notJoined

        /// The network name, or `nil` whenever MacLock cannot read one. Every `nil`
        /// here means "no trusted network can match", which is what keeps an
        /// unreadable name from silently disarming MacLock.
        var ssid: String? {
            if case .joined(let name) = self { return name }
            return nil
        }

        /// Why there is no name to show, in words the user can act on.
        var unavailabilityMessage: String? {
            switch self {
            case .joined: nil
            case .noHardware: "This Mac has no Wi-Fi interface, so it can never be on a trusted network."
            case .needsLocationAccess: "MacLock cannot read the Wi-Fi network name until Location access is granted - macOS treats the network name as location data. Until then MacLock keeps watching your watch everywhere."
            case .wifiOff: "Wi-Fi is switched off, so MacLock keeps watching your watch."
            case .notJoined: "Not connected to a Wi-Fi network."
            }
        }
    }

    /// Whether Location access still has to be asked for, or has been refused.
    enum LocationAccess: Equatable {
        case granted
        /// Never asked. Asking shows the system prompt.
        case notAsked
        /// Refused or restricted. Only System Settings can change it now.
        case refused
    }

    private(set) var network: Network = .needsLocationAccess
    private(set) var locationAccess: LocationAccess = .notAsked

    private let locationManager = CLLocationManager()
    private let wifiClient = CWWiFiClient.shared()
    private let log = Logger(subsystem: "au.com.yumait.MacLock", category: "WiFi")

    /// Suppress repeat log lines for state that has not changed.
    private var lastLoggedNetwork: Network?
    private var lastLoggedAuthorizationStatus: CLAuthorizationStatus?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        readAuthorization()
        refresh()
    }

    /// Re-reads the current network. Called from the controller's existing one-second
    /// tick rather than on a timer of its own: the read is a cheap query to the Wi-Fi
    /// daemon, and one clock driving every periodic read is what keeps MacLock's
    /// decisions consistent within a tick.
    func refresh() {
        let next = readNetwork()
        guard next != network else { return }
        network = next

        if next != lastLoggedNetwork {
            lastLoggedNetwork = next
            switch next {
            case .joined(let name):
                log.notice("Joined Wi-Fi network \(name, privacy: .private(mask: .hash))")
            default:
                log.notice("No readable Wi-Fi network: \(String(describing: next), privacy: .public)")
            }
        }
    }

    /// Shows the system's Location prompt, if it has not been answered already.
    ///
    /// Once refused, only System Settings can change the answer -- the system will not
    /// prompt a second time -- so the UI offers that route instead.
    ///
    /// `requestWhenInUseAuthorization()` alone does not raise the prompt on macOS;
    /// the system shows it when an app actually starts a location service. So one is
    /// started and then stopped the moment the answer arrives, in
    /// ``locationManagerDidChangeAuthorization(_:)``. Accuracy is set as coarse as
    /// CoreLocation allows because MacLock never reads a location -- it only needs the
    /// permission that makes the network name legible.
    func requestLocationAccess() {
        guard locationAccess == .notAsked else { return }
        log.notice("Requesting Location authorization")
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    /// The order here is the whole point. Authorisation is checked before association,
    /// because an unauthorised read and a Mac that is genuinely off Wi-Fi both look
    /// like a `nil` SSID, and telling the user "not connected" when the truth is
    /// "not allowed to look" would send them to fix the wrong thing. The radio's own
    /// power state is checked first because it is readable without permission and is
    /// the more useful thing to be told when both are true.
    private func readNetwork() -> Network {
        guard let interface = wifiClient.interface() else { return .noHardware }
        guard interface.powerOn() else { return .wifiOff }
        guard locationAccess == .granted else { return .needsLocationAccess }
        guard let ssid = interface.ssid(), !ssid.isEmpty else { return .notJoined }
        return .joined(ssid)
    }

    private func readAuthorization() {
        let status = locationManager.authorizationStatus
        if status != lastLoggedAuthorizationStatus {
            lastLoggedAuthorizationStatus = status
            log.notice("Location authorization: \(status.rawValue, privacy: .public)")
        }

        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            locationAccess = .granted
        case .notDetermined:
            locationAccess = .notAsked
        case .denied, .restricted:
            locationAccess = .refused
        @unknown default:
            // An unrecognised status is not permission. Reading the name would fail
            // anyway, and treating it as granted would report `.notJoined` for a Mac
            // sitting on its home network.
            locationAccess = .refused
        }
    }
}

extension WiFiMonitor: CLLocationManagerDelegate {

    /// MacLock never reads a location, so an update is nothing to act on and a
    /// failure to get one is not an error it should report.
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            // The service only existed to raise the prompt. The answer has arrived, so
            // MacLock stops asking the Mac where it is.
            locationManager.stopUpdatingLocation()
            readAuthorization()
            // The name becomes readable the instant access is granted; without this
            // the user would have granted it and still be told MacLock cannot see
            // the network until something else happened to trigger a read.
            refresh()
        }
    }
}
