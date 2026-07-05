# elmulator — Swift package

A SwiftPM package for emulating an ELM327 OBD2 adapter over TCP and Bluetooth LE, plus an in-process fake BLE stack for radio-free CI. Requires Swift 6, macOS 14+ / iOS 17+.

## Add it

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/elmulator/elmulator.git", from: "0.1.0"),
],
```

> The package manifest lives in `swift/`. If consuming from this monorepo directly, point at that subdirectory.

## Products

| Product | Import | Platforms | Purpose |
|---|---|---|---|
| `Elmulator` | `import Elmulator` | iOS/macOS | Scenario model (`FakeELMScenario`) + pure engine (`FakeELMScenarioEngine`). No I/O. |
| `ElmulatorTCP` | `import ElmulatorTCP` | iOS/macOS | `FakeELMTCPServer` — host a scenario over localhost TCP in-process. |
| `ElmulatorBLE` | `import ElmulatorBLE` | iOS/macOS | GATT profile, `BLEConnectionStateMachine` (pure), `BLEStack` protocol, and `makeCoreBluetoothStack()` (real central). |
| `ElmulatorBLETestSupport` | `import ElmulatorBLETestSupport` | iOS/macOS | `FakeBLEStack` — the in-process fake central. Depend on it from your test target. |

## Executables

```bash
swift run elmulator-tcp --scenario ../scenarios/p0420_basic.scenario.json --port 35000
swift run elmulator-ble --scenario ../scenarios/p0420_basic.scenario.json   # macOS, real BLE
```

## Design

The `BLEStack` protocol is the seam. Your production Bluetooth code (and the pure `BLEConnectionStateMachine`) run against `BLEStack`; in the app you back it with `makeCoreBluetoothStack()`, in tests with `FakeBLEStack`. Nothing in this package depends on any host-app module — the connection state machine raises its own `BLETransportError`, which you map to your app's error model at the boundary.

## Test

```bash
swift test   # 28 tests: engine, TCP line framing, BLE state machine, fake-stack integration
```
