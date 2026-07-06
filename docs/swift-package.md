# The elmulator Swift package

A SwiftPM package for emulating an ELM327 OBD2 adapter over TCP and Bluetooth LE, plus an in-process fake BLE stack for radio-free CI. Requires Swift 6, macOS 14+ / iOS 17+.

## Add it

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/qadanm/elmulator.git", from: "0.2.0"),
],
```

> The `Package.swift` is at the repository root, so the URL above is all you need.

## Products

| Product | Import | Platforms | Purpose |
|---|---|---|---|
| `Elmulator` | `import Elmulator` | iOS/macOS | Scenario model (`Scenario`) + pure engine (`ScenarioEngine`). No I/O. |
| `ElmulatorTCP` | `import ElmulatorTCP` | iOS/macOS | `TCPServer`, host a scenario over localhost TCP in-process. |
| `ElmulatorTestSupport` | `import ElmulatorTestSupport` | iOS/macOS | `Conversation` (in-process, no sockets) and `Client` (TCP), to drive the emulator in a few lines. |
| `ElmulatorBLE` | `import ElmulatorBLE` | iOS/macOS | GATT profile, `ConnectionStateMachine` (pure), `CentralStack` protocol, and `makeCoreBluetoothStack()` (real central). |
| `ElmulatorBLETestSupport` | `import ElmulatorBLETestSupport` | iOS/macOS | `FakeCentral`, the in-process fake central. Depend on it from your test target. |
| `ElmulatorCoreBluetoothMock` | `import ElmulatorCoreBluetoothMock` | iOS/macOS | `ElmulatorMockPeripheral`, which bridges a scenario to [CoreBluetooth-Mock](https://github.com/NordicSemiconductor/IOS-CoreBluetooth-Mock) so your real `CBCentralManager` code runs against a scripted ELM327. Pulls in CoreBluetooth-Mock (this product only). |

## Executables

```bash
swift run elmulator-tcp --scenario ../scenarios/p0420_basic.scenario.json --port 35000
swift run elmulator-ble --scenario ../scenarios/p0420_basic.scenario.json   # macOS, real BLE
```

## Design

The `CentralStack` protocol is the seam. Your production Bluetooth code (and the pure `ConnectionStateMachine`) run against `CentralStack`; in the app you back it with `makeCoreBluetoothStack()`, in tests with `FakeCentral`. Nothing in this package depends on any host-app module. The connection state machine raises its own `ConnectionError`, which you map to your app's error model at the boundary.

## Test

```bash
swift test   # engine, TCP line framing, BLE state machine, fake-stack and CoreBluetooth-Mock integration
```
