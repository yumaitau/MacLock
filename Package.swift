// swift-tools-version: 6.0
import PackageDescription

// ProximityCore's sources live under MacLock/ProximityCore so the Xcode app target
// picks them up through its file-system-synchronized group, while this manifest
// exposes the same files as a library for `swift test`. The app therefore never
// imports ProximityCore -- it compiles those files into its own module.
//
// swiftLanguageModes is pinned to .v5 to match the app target's SWIFT_VERSION = 5.0;
// leaving it unpinned would check the same sources under Swift 6 strict concurrency
// here and Swift 5 in Xcode.
//
// SHORTCUT: sources are shared with the app target rather than linked as a real
// package dependency, which keeps the Xcode project free of structural edits but
// means ProximityCore cannot take dependencies of its own. Convert to a conventional
// Sources/ProximityCore/ layout with an XCLocalSwiftPackageReference the moment it
// needs one.
let package = Package(
    name: "ProximityCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ProximityCore", targets: ["ProximityCore"])
    ],
    targets: [
        .target(
            name: "ProximityCore",
            path: "MacLock/ProximityCore"
        ),
        .testTarget(
            name: "ProximityCoreTests",
            dependencies: ["ProximityCore"],
            path: "Tests/ProximityCoreTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
