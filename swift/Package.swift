// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Elmulator",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        // Pure scenario model + request→reply engine. No I/O.
        .library(name: "Elmulator", targets: ["Elmulator"]),
        // Localhost TCP host for a scenario (in-process, for tests).
        .library(name: "ElmulatorTCP", targets: ["ElmulatorTCP"]),
        // BLE transport kit: GATT profile, connection state machine,
        // BLEStack protocol, and the real CoreBluetooth central.
        .library(name: "ElmulatorBLE", targets: ["ElmulatorBLE"]),
        // The in-process fake BLE central — swap it for the real one in tests.
        .library(name: "ElmulatorBLETestSupport", targets: ["ElmulatorBLETestSupport"]),
        // CLI TCP server (parity with `elmulator serve` in Python).
        .executable(name: "elmulator-tcp", targets: ["elmulator-tcp"]),
        // macOS executable: advertise a scenario as a real BLE peripheral.
        .executable(name: "elmulator-ble", targets: ["elmulator-ble"]),
    ],
    targets: [
        .target(name: "Elmulator"),
        .target(name: "ElmulatorTCP", dependencies: ["Elmulator"]),
        .target(name: "ElmulatorBLE"),
        .target(
            name: "ElmulatorBLETestSupport",
            dependencies: ["Elmulator", "ElmulatorBLE"]
        ),
        .executableTarget(
            name: "elmulator-tcp",
            dependencies: ["Elmulator", "ElmulatorTCP"]
        ),
        .executableTarget(
            name: "elmulator-ble",
            dependencies: ["Elmulator", "ElmulatorBLE"]
        ),
        .testTarget(
            name: "ElmulatorTests",
            dependencies: ["Elmulator", "ElmulatorTCP"]
        ),
        .testTarget(
            name: "ElmulatorBLETests",
            dependencies: ["ElmulatorBLE", "ElmulatorBLETestSupport", "Elmulator"]
        ),
    ]
)
