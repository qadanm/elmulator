// swift-tools-version: 6.0
import PackageDescription

// A copy-this example: a realistic ELM327 BLE client (ObdSampleClient) written
// in pure CoreBluetooth-Mock, with a test suite that drives it against scripted
// elmulator scenarios — on CI, with no Bluetooth radio.
let package = Package(
    name: "elmulator-ios-ci-example",
    platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: [
        .package(path: "../../swift"),  // elmulator (this repo)
        .package(
            url: "https://github.com/NordicSemiconductor/IOS-CoreBluetooth-Mock.git",
            from: "1.0.0"
        ),
    ],
    targets: [
        // The "app under test": production Bluetooth code, no elmulator import.
        .target(
            name: "ObdSampleClient",
            dependencies: [
                .product(name: "CoreBluetoothMock", package: "IOS-CoreBluetooth-Mock"),
            ]
        ),
        // The test target injects the scripted adapter.
        .testTarget(
            name: "ObdSampleClientTests",
            dependencies: [
                "ObdSampleClient",
                .product(name: "Elmulator", package: "swift"),
                .product(name: "ElmulatorCoreBluetoothMock", package: "swift"),
                .product(name: "CoreBluetoothMock", package: "IOS-CoreBluetooth-Mock"),
            ]
        ),
    ]
)
