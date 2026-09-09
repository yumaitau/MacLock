import Testing

@testable import ProximityCore

@Suite("TrustedNetworks")
struct TrustedNetworksTests {

    @Test("A network the user listed is trusted")
    func listedNetworkIsTrusted() {
        #expect(isOnTrustedNetwork(ssid: "Home", trusted: ["Office", "Home"]))
    }

    @Test("A network the user did not list is not trusted")
    func unlistedNetworkIsNotTrusted() {
        #expect(!isOnTrustedNetwork(ssid: "AirportFreeWiFi", trusted: ["Office", "Home"]))
    }

    /// The misfire this whole feature could produce: macOS refuses to name the
    /// network - Location access not granted, Wi-Fi off, Ethernet only - and MacLock
    /// treats not knowing as being at home, quietly guarding nothing, everywhere.
    @Test("An unreadable network name is never trusted, however long the list")
    func unknownNetworkIsNeverTrusted() {
        #expect(!isOnTrustedNetwork(ssid: nil, trusted: ["Office", "Home"]))
        #expect(!isOnTrustedNetwork(ssid: nil, trusted: []))
        #expect(!isOnTrustedNetwork(ssid: "", trusted: ["Office", "Home", ""]))
    }

    @Test("An empty trusted list never matches")
    func emptyListNeverMatches() {
        #expect(!isOnTrustedNetwork(ssid: "Home", trusted: []))
    }

    /// Standing down is MacLock giving up its entire job, so a network that merely
    /// resembles a trusted one does not count.
    @Test("Matching is exact, not approximate")
    func matchingIsExact() {
        #expect(!isOnTrustedNetwork(ssid: "home", trusted: ["Home"]))
        #expect(!isOnTrustedNetwork(ssid: "Home Guest", trusted: ["Home"]))
        #expect(!isOnTrustedNetwork(ssid: "Home ", trusted: ["Home"]))
    }

    @Test("A typed name is stripped of surrounding whitespace")
    func typedNameIsTrimmed() {
        #expect(normalizedNetworkName("  Home  ") == "Home")
        #expect(normalizedNetworkName("Home") == "Home")
    }

    @Test("A name that is blank once trimmed is refused")
    func blankNameIsRefused() {
        #expect(normalizedNetworkName("") == nil)
        #expect(normalizedNetworkName("   ") == nil)
        #expect(normalizedNetworkName("\t\n ") == nil)
    }

    @Test("Adding a network appends it, trimmed, at the end")
    func addingAppendsTrimmedName() {
        #expect(addingTrustedNetwork("  Office Wi-Fi ", to: ["Home"]) == ["Home", "Office Wi-Fi"])
        #expect(addingTrustedNetwork("Home", to: []) == ["Home"])
    }

    @Test("Adding a blank name is refused, and says so distinctly from a duplicate")
    func addingBlankNameIsRefused() {
        #expect(addingTrustedNetwork("", to: ["Home"]) == nil)
        #expect(addingTrustedNetwork("   ", to: ["Home"]) == nil)
        // A duplicate is not a refusal: it returns the list, unchanged.
        #expect(addingTrustedNetwork("Home", to: ["Home"]) == ["Home"])
    }

    @Test("Adding a network already trusted does not duplicate it")
    func addingDuplicateDoesNotDuplicate() {
        #expect(addingTrustedNetwork("  Home  ", to: ["Home", "Office"]) == ["Home", "Office"])
    }

    @Test("Removing drops only the exact match")
    func removingDropsOnlyTheExactMatch() {
        #expect(removingTrustedNetwork("Home", from: ["Home", "home", "Office"]) == ["home", "Office"])
        #expect(removingTrustedNetwork("Home ", from: ["Home"]) == ["Home"])
    }

    @Test("Removing a network that is not listed changes nothing")
    func removingAbsentNetworkChangesNothing() {
        #expect(removingTrustedNetwork("Cafe", from: ["Home", "Office"]) == ["Home", "Office"])
        #expect(removingTrustedNetwork("Cafe", from: []) == [])
    }

    /// A trimmed name is stored, so it is also what has to match. Round-tripping the
    /// name the user typed through storage must not stop it matching the real network.
    @Test("A name that survives entry matches the network it names")
    func normalizedNameMatchesItsNetwork() {
        let stored = normalizedNetworkName("  Office Wi-Fi ")
        #expect(stored == "Office Wi-Fi")
        #expect(isOnTrustedNetwork(ssid: "Office Wi-Fi", trusted: [stored!]))
    }
}
