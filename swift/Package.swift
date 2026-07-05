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
        // Bridge to Nordic's CoreBluetooth-Mock: test an app's real
        // CoreBluetooth code against a scripted ELM327, no radio.
        .library(name: "ElmulatorCoreBluetoothMock", targets: ["ElmulatorCoreBluetoothMock"]),
        // CLI TCP server (parity with `elmulator serve` in Python).
        .executable(name: "elmulator-tcp", targets: ["elmulator-tcp"]),
        // macOS executable: advertise a scenario as a real BLE peripheral.
        .executable(name: "elmulator-ble", targets: ["elmulator-ble"]),
    ],
    dependencies: [
        // Only the ElmulatorCoreBluetoothMock target links this; the pure
        // engine / TCP / BLE products do not depend on it.
        .package(
            url: "https://github.com/NordicSemiconductor/IOS-CoreBluetooth-Mock.git",
            from: "1.0.0"
        ),
    ],
    targets: [
        .target(name: "Elmulator"),
        .target(name: "ElmulatorTCP", dependencies: ["Elmulator"]),
        .target(name: "ElmulatorBLE"),
        .target(
            name: "ElmulatorBLETestSupport",
            dependencies: ["Elmulator", "ElmulatorBLE"]
        ),
        .target(
            name: "ElmulatorCoreBluetoothMock",
            dependencies: [
                "Elmulator",
                "ElmulatorBLE",
                .product(name: "CoreBluetoothMock", package: "IOS-CoreBluetooth-Mock"),
            ]
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
